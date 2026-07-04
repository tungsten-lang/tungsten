# frozen_string_literal: true

require "bigdecimal"

module Tungsten
  class Currency
    include Comparable

    attr_reader :value, :symbol

    # Currency families: sub-units share a family with their parent
    FAMILIES = {
      "¢" => "$",        # cent → dollar
      "p£" => "£",       # pence → pound
      "c€" => "€",       # centime → euro
      "s¥" => "¥",       # sen → yen
      "p₹" => "₹",       # paisa → rupee
    }.freeze

    SUB_UNIT_FACTOR = {
      "¢" => BigDecimal("0.01"),     # 100 cents = 1 dollar
      "p£" => BigDecimal("0.01"),    # 100 pence = 1 pound
      "c€" => BigDecimal("0.01"),    # 100 centimes = 1 euro
      "s¥" => BigDecimal("0.01"),    # 100 sen = 1 yen (historically)
      "p₹" => BigDecimal("0.01"),    # 100 paise = 1 rupee
    }.freeze

    # Sub-unit name aliases: word → internal symbol
    SUB_UNIT_NAMES = {
      "pence" => "p£", "penny" => "p£",
      "centime" => "c€", "centimes" => "c€",
      "sen" => "s¥",
      "paisa" => "p₹", "paise" => "p₹",
    }.freeze

    SUFFIX_SYMBOLS = Set.new(%w[¢]).freeze

    DECIMAL_PLACES = {
      "$" => 2, "€" => 2, "£" => 2, "₹" => 2,
      "¥" => 0, "¢" => 0,
      "p£" => 0, "c€" => 0, "s¥" => 0, "p₹" => 0,
    }.freeze

    def initialize(value, symbol)
      @value = value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
      @symbol = symbol
    end

    def +(other)
      case other
      when Currency
        ensure_compatible!(other)
        converted = convert_to_self(other)
        Currency.new(@value + converted, @symbol)
      when Percentage
        Currency.new(@value * (1 + other.ratio), @symbol)
      when Numeric
        Currency.new(@value + BigDecimal(other.to_s), @symbol)
      else
        raise TypeError, "cannot add #{other.class} to Currency"
      end
    end

    def -(other)
      case other
      when Currency
        ensure_compatible!(other)
        converted = convert_to_self(other)
        Currency.new(@value - converted, @symbol)
      when Percentage
        Currency.new(@value * (1 - other.ratio), @symbol)
      when Numeric
        Currency.new(@value - BigDecimal(other.to_s), @symbol)
      else
        raise TypeError, "cannot subtract #{other.class} from Currency"
      end
    end

    def *(other)
      case other
      when Numeric
        Currency.new(@value * BigDecimal(other.to_s), @symbol)
      when Quantity
        as_quantity * other
      else
        raise TypeError, "cannot multiply Currency by #{other.class}"
      end
    end

    def /(other)
      case other
      when Currency
        ensure_compatible!(other)
        converted = convert_to_self(other)
        result = @value / converted
        # Return plain numeric: integer if exact, otherwise float
        result.denominator == 1 ? result.to_i : result.to_f
      when Numeric
        Currency.new(@value / BigDecimal(other.to_s), @symbol)
      when Quantity
        as_quantity / other
      else
        raise TypeError, "cannot divide Currency by #{other.class}"
      end
    end

    def -@
      Currency.new(-@value, @symbol)
    end

    def coerce(other)
      case other
      when Numeric
        [CurrencyCoerced.new(other), self]
      else
        raise TypeError, "#{other.class} can't be coerced into Currency"
      end
    end

    def <=>(other)
      return nil unless other.is_a?(Currency) && same_family?(other)
      to_base_value <=> other.to_base_value
    end

    def ==(other)
      return false unless other.is_a?(Currency) && same_family?(other)
      to_base_value == other.to_base_value
    end

    def to_s
      approx, digits = format_value
      if SUFFIX_SYMBOLS.include?(@symbol)
        "#{approx}#{digits}#{@symbol}"
      else
        "#{approx}#{@symbol}#{digits}"
      end
    end

    def inspect
      to_s
    end

    protected

    def to_base_value
      factor = SUB_UNIT_FACTOR[@symbol]
      factor ? @value * factor : @value
    end

    private

    def family
      FAMILIES[@symbol] || @symbol
    end

    def same_family?(other)
      family == other.send(:family)
    end

    def ensure_compatible!(other)
      unless same_family?(other)
        raise TypeError, "cannot combine #{@symbol} with #{other.symbol}"
      end
    end

    def convert_to_self(other)
      if @symbol == other.symbol
        other.value
      else
        base = other.to_base_value
        my_factor = SUB_UNIT_FACTOR[@symbol]
        my_factor ? base / my_factor : base
      end
    end

    # Convert this Currency to a Quantity whose dimension is a custom tag named
    # after the currency symbol's ISO code (or fallback to the symbol itself).
    # Lets Currency interoperate with Quantity arithmetic — e.g., `$5 / 1 hour`
    # returns a Quantity with dim USD·time⁻¹.
    CURRENCY_DIM_NAMES = {
      "$" => "USD", "€" => "EUR", "£" => "GBP", "¥" => "JPY", "₹" => "INR",
      "¢" => "USD", "p£" => "GBP", "c€" => "EUR", "s¥" => "JPY", "p₹" => "INR",
    }.freeze

    def as_quantity
      iso = CURRENCY_DIM_NAMES[@symbol] || @symbol
      sub_factor = SUB_UNIT_FACTOR[@symbol] || BigDecimal("1")
      dim = Units::Dimension.custom("currency_#{iso}")
      unit = Units::CompoundUnit.new(
        dimension: dim,
        factor: sub_factor,
        components: { iso => 1 }
      )
      Quantity.new(@value, unit)
    end

    def format_value
      places = DECIMAL_PLACES[@symbol] || 2
      places = 0 if places > 0 && @value.abs >= 1000
      rounded = @value.round(places)
      approx = rounded != @value ? "≈" : ""

      digits = if places == 0
                 rounded.to_i.to_s
               else
                 str = rounded.to_s("F")
                 parts = str.split(".")
                 parts[1] = (parts[1] || "0").ljust(places, "0")[0, places]
                 parts.join(".")
               end
      [approx, digits]
    end

    # Wrapper to enable `5 * $10` via coerce
    class CurrencyCoerced
      def initialize(value)
        @value = value
      end

      def *(currency)
        currency * @value
      end

      def +(currency)
        currency + @value
      end

      def -(currency)
        Currency.new(BigDecimal(@value.to_s) - currency.value, currency.symbol)
      end
    end
  end
end
