# frozen_string_literal: true

require "date"

module Tungsten
  class Date < Literal
    def initialize(value)
      @value = value.is_a?(::Date) ? value : ::Date.parse(value.to_s)
    end

    def to_s = @value.strftime("%Y-%m-%d")

    def +(other)
      case other
      when Duration
        result = other.apply_months(@value.to_datetime)
        date_or_datetime(result + Rational(other.seconds, 86400))
      when Quantity
        seconds = quantity_to_seconds(other)
        date_or_datetime(@value.to_datetime + Rational(seconds, 86400))
      else
        Date.new(@value + other)
      end
    end

    def -(other)
      case other
      when Duration
        result = @value.to_datetime >> (-other.months)
        date_or_datetime(result - Rational(other.seconds, 86400))
      when Quantity
        seconds = quantity_to_seconds(other)
        date_or_datetime(@value.to_datetime - Rational(seconds, 86400))
      when Date
        diff_days = @value - other.value
        Quantity.new(diff_days.to_f, Units.parse("d"))
      else
        Date.new(@value - other)
      end
    end

    def succ = Date.new(@value + 1)
    def <=>(other) = @value <=> (other.is_a?(Date) ? other.value : other)

    def short = @value.strftime("%a, %b %-d, %Y")

    def long
      day = @value.day
      suffix = case day
               when 1, 21, 31 then "ˢᵗ"
               when 2, 22 then "ⁿᵈ"
               when 3, 23 then "ʳᵈ"
               else "ᵗʰ"
               end
      @value.strftime("%A, %B %-d") + suffix + @value.strftime(", %Y")
    end

    private

    def date_or_datetime(result)
      if result == result.to_date
        Date.new(result.to_date)
      else
        DateTime.new(result)
      end
    end

    def quantity_to_seconds(qty)
      unless qty.unit.dimension == Units::TIME
        raise DimensionError, "cannot add #{Units.dimension_name(qty.unit.dimension)} to Date"
      end
      (qty.value * qty.unit.factor).to_f
    end
  end
end
