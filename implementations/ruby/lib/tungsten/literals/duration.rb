# frozen_string_literal: true

require "strscan"

module Tungsten
  class Duration
    include Comparable

    # @months: Integer — nominal months (years * 12 + months)
    # @seconds: Rational — fixed time (weeks, days, hours, minutes, seconds, ms, µs, ns)
    attr_reader :months, :seconds

    # Fixed-length unit factors in seconds
    UNIT_SECONDS = {
      "w"  => Rational(604_800),
      "d"  => Rational(86_400),
      "h"  => Rational(3_600),
      "m"  => Rational(60),
      "s"  => Rational(1),
      "ms" => Rational(1, 1_000),
      "µs" => Rational(1, 1_000_000),
      "ns" => Rational(1, 1_000_000_000),
    }.freeze

    # Nominal unit factors in months
    UNIT_MONTHS = {
      "y"  => 12,
      "mo" => 1,
    }.freeze

    DISPLAY_ORDER_MONTHS = %w[y mo].freeze
    DISPLAY_ORDER_SECONDS = %w[w d h m s ms µs ns].freeze

    def initialize(months, seconds)
      @months = months
      @seconds = seconds.is_a?(Rational) ? seconds : Rational(seconds)
    end

    # Parse a compound duration string like "2h15m30s" or ISO 8601 "P1DT2H30M"
    def self.parse(str)
      str.start_with?("P") ? parse_iso(str) : parse_compact(str)
    end

    def self.parse_compact(str)
      months = 0
      seconds = Rational(0)
      scanner = StringScanner.new(str)

      until scanner.eos?
        num = scanner.scan(/\d+(?:\.\d+)?/)
        raise Error, "invalid duration: #{str}" unless num

        unit = scanner.scan(/mo|ms|µs|ns|m(?!s|o)|[ywdhms]/)
        raise Error, "invalid duration unit in: #{str}" unless unit

        if UNIT_MONTHS.key?(unit)
          months += Rational(num) * UNIT_MONTHS.fetch(unit)
        else
          seconds += Rational(num) * UNIT_SECONDS.fetch(unit)
        end
      end

      new(months.to_i, seconds)
    end

    ISO_MAP = { "Y" => "y", "W" => "w", "D" => "d", "H" => "h", "M" => "m", "S" => "s" }.freeze

    def self.parse_iso(str)
      months = 0
      seconds = Rational(0)
      scanner = StringScanner.new(str)
      scanner.scan(/P/) || raise(Error, "invalid ISO 8601 duration: #{str}")

      in_time = false
      until scanner.eos?
        if scanner.scan(/T/)
          in_time = true
          next
        end

        num = scanner.scan(/\d+(?:\.\d+)?/)
        raise Error, "invalid ISO 8601 duration: #{str}" unless num

        iso_unit = scanner.scan(/[YMWDHS]/)
        raise Error, "invalid ISO 8601 duration: #{str}" unless iso_unit

        # M means months in date part, minutes in time part
        unit = if iso_unit == "M"
                 in_time ? "m" : "mo"
               else
                 ISO_MAP.fetch(iso_unit)
               end

        if UNIT_MONTHS.key?(unit)
          months += Rational(num) * UNIT_MONTHS.fetch(unit)
        else
          seconds += Rational(num) * UNIT_SECONDS.fetch(unit)
        end
      end

      new(months.to_i, seconds)
    end

    def +(other)
      case other
      when Duration
        Duration.new(@months + other.months, @seconds + other.seconds)
      when Date
        other + self
      when DateTime
        other + self
      when Quantity
        ensure_time_quantity!(other, "add")
        Duration.new(@months, @seconds + quantity_to_seconds(other))
      else
        raise DimensionError, "cannot add #{other.class} to Duration"
      end
    end

    def -(other)
      case other
      when Duration
        Duration.new(@months - other.months, @seconds - other.seconds)
      when Quantity
        ensure_time_quantity!(other, "subtract")
        Duration.new(@months, @seconds - quantity_to_seconds(other))
      else
        raise DimensionError, "cannot subtract #{other.class} from Duration"
      end
    end

    def *(other)
      case other
      when Numeric
        Duration.new(@months * other, @seconds * other)
      when Quantity
        # Treat self as Quantity[time] — months are rejected since their length
        # depends on calendar context (use Duration math directly for those).
        raise DimensionError, "cannot multiply a Duration with nominal months by a Quantity (use a fixed-time duration)" if @months != 0
        s_unit = Units::CompoundUnit.new(dimension: Units::TIME, factor: 1, components: {"s" => 1})
        Quantity.new(@seconds, s_unit) * other
      else
        raise DimensionError, "cannot multiply Duration by #{other.class}"
      end
    end

    def /(other)
      case other
      when Duration
        if other.months == 0 && @months == 0
          (@seconds / other.seconds).to_r
        elsif other.seconds == 0 && @seconds == 0
          Rational(@months, other.months)
        else
          raise DimensionError, "cannot divide mixed durations (nominal and fixed components)"
        end
      when Numeric
        Duration.new(@months / other, @seconds / other)
      when Quantity
        # Duration / Quantity[time] = dimensionless; Duration / Quantity[other] = Quantity[time/other].
        raise DimensionError, "cannot divide a Duration with nominal months by a Quantity" if @months != 0
        s_unit = Units::CompoundUnit.new(dimension: Units::TIME, factor: 1, components: {"s" => 1})
        Quantity.new(@seconds, s_unit) / other
      else
        raise DimensionError, "cannot divide Duration by #{other.class}"
      end
    end

    private

    def ensure_time_quantity!(qty, verb)
      return if qty.unit.dimension == Units::TIME
      raise DimensionError,
            "cannot #{verb} #{Units.dimension_name(qty.unit.dimension)} (#{qty.unit}) and a Duration"
    end

    def quantity_to_seconds(qty)
      qty.value * qty.unit.factor + qty.unit.offset
    end

    public

    def -@
      Duration.new(-@months, -@seconds)
    end

    def coerce(other)
      case other
      when Numeric
        [CoercedScalar.new(other), self]
      else
        raise TypeError, "#{other.class} can't be coerced into Duration"
      end
    end

    def <=>(other)
      return nil unless other.is_a?(Duration)
      return nil unless @months == other.months || (@seconds == 0 && other.seconds == 0) || (@months == 0 && other.months == 0)

      if @months == other.months
        @seconds <=> other.seconds
      else
        @months <=> other.months
      end
    end

    def ==(other)
      case other
      when Duration then @months == other.months && @seconds == other.seconds
      else false
      end
    end

    def hash = [@months, @seconds].hash
    def eql?(other) = other.is_a?(Duration) && @months == other.months && @seconds == other.seconds

    def to_s
      return "0s" if @months == 0 && @seconds == 0

      parts = []

      # Nominal components
      remaining_months = @months.abs
      DISPLAY_ORDER_MONTHS.each do |unit|
        factor = UNIT_MONTHS[unit]
        count = remaining_months / factor
        next if count == 0

        remaining_months -= count * factor
        parts << "#{count}#{unit}"
      end

      # Fixed components
      remaining_seconds = @seconds.abs
      DISPLAY_ORDER_SECONDS.each do |unit|
        factor = UNIT_SECONDS[unit]
        next if remaining_seconds < factor

        count = (remaining_seconds / factor).to_i
        next if count == 0

        remaining_seconds -= count * factor
        parts << "#{count}#{unit}"
      end

      negative = (@months < 0 || @seconds < 0)
      negative ? "-#{parts.join}" : parts.join
    end

    def inspect = to_s

    # Convert to a Quantity in seconds (only if no nominal months)
    def to_quantity
      raise DimensionError, "cannot convert duration with months/years to seconds" unless @months == 0
      Quantity.new(@seconds.to_f, Units.parse("s"))
    end

    # Add nominal months to a Ruby Date/DateTime using calendar arithmetic
    def apply_months(date_value)
      return date_value if @months == 0
      date_value >> @months
    end

    class CoercedScalar
      def initialize(value)
        @value = value
      end

      def *(duration)
        Duration.new(@value * duration.months, @value * duration.seconds)
      end

      def +(duration)
        raise DimensionError, "cannot add scalar to Duration"
      end

      def -(duration)
        raise DimensionError, "cannot subtract Duration from scalar"
      end
    end
  end
end
