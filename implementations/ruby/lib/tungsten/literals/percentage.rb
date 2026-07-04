# frozen_string_literal: true

module Tungsten
  class Percentage
    include Comparable

    attr_reader :value

    def initialize(value)
      @value = value.is_a?(Float) ? value : value.to_f
    end

    # ratio: 15% → 0.15
    def ratio
      @value / 100.0
    end

    # Percentage ± Percentage → Percentage (additive: 20% + 5% = 25%)
    def +(other)
      case other
      when Percentage
        Percentage.new(@value + other.value)
      else
        raise TypeError, "cannot add #{other.class} to Percentage"
      end
    end

    def -(other)
      case other
      when Percentage
        Percentage.new(@value - other.value)
      else
        raise TypeError, "cannot subtract #{other.class} from Percentage"
      end
    end

    def *(other)
      case other
      when Numeric
        ratio * other
      else
        raise TypeError, "cannot multiply Percentage by #{other.class}"
      end
    end

    def -@
      Percentage.new(-@value)
    end

    # Enable calculator semantics:
    #   100 - 15% → PercentageCoerced(100).-(Pct(15)) → 100 × 0.85 = 85
    #   100 + 10% → PercentageCoerced(100).+(Pct(10)) → 100 × 1.10 = 110
    def coerce(other)
      case other
      when Numeric
        [PercentageCoerced.new(other), self]
      else
        raise TypeError, "#{other.class} can't be coerced into Percentage"
      end
    end

    def <=>(other)
      return nil unless other.is_a?(Percentage)
      @value <=> other.value
    end

    def ==(other)
      other.is_a?(Percentage) && @value == other.value
    end

    def to_s
      formatted = @value == @value.to_i ? @value.to_i.to_s : @value.to_s
      "#{formatted}%"
    end

    def inspect
      to_s
    end

    # Wrapper for calculator-style percent arithmetic on left-side values
    class PercentageCoerced
      def initialize(value)
        @value = value
      end

      def +(percentage)
        @value * (1 + percentage.ratio)
      end

      def -(percentage)
        @value * (1 - percentage.ratio)
      end

      def *(percentage)
        @value * percentage.ratio
      end
    end
  end
end
