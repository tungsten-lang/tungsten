# frozen_string_literal: true

module Tungsten
  class DateTime < Literal
    def +(other)
      case other
      when Duration
        result = other.apply_months(@value)
        DateTime.new(result + Rational(other.seconds, 86400))
      when Quantity
        seconds = quantity_to_seconds(other)
        DateTime.new(@value + Rational(seconds, 86400))
      else
        DateTime.new(@value + other)
      end
    end

    def -(other)
      case other
      when Duration
        result = @value >> (-other.months)
        DateTime.new(result - Rational(other.seconds, 86400))
      when Quantity
        seconds = quantity_to_seconds(other)
        DateTime.new(@value - Rational(seconds, 86400))
      when DateTime
        diff_days = @value - other.value
        Quantity.new(diff_days.to_f * 86400, Units.parse("s"))
      else
        DateTime.new(@value - other)
      end
    end

    private

    def quantity_to_seconds(qty)
      unless qty.unit.dimension == Units::TIME
        raise DimensionError, "cannot add #{Units.dimension_name(qty.unit.dimension)} to DateTime"
      end
      (qty.value * qty.unit.factor).to_f
    end
  end
end
