# frozen_string_literal: true

require "date"

module Tungsten
  class DateTime < Literal
    def initialize(value)
      case value
      when ::DateTime
        @value = value
        @leap_second = false
      when String
        parse_iso(value)
      else
        @value = value
        @leap_second = false
      end
    end

    def sec
      @leap_second ? 60 : @value.sec
    end
    alias second sec

    def tz
      (@value.offset * 24 * 60).to_i
    end

    def to_s
      stamp = format("%04d-%02d-%02dT%02d:%02d:%02d",
                     @value.year, @value.month, @value.day,
                     @value.hour, @value.min, second)
      off = tz
      if off == 0
        "#{stamp}Z"
      else
        sign = off.negative? ? "-" : "+"
        mag = off.abs
        format("%s%s%02d:%02d", stamp, sign, mag / 60, mag % 60)
      end
    end

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

    def parse_iso(text)
      tz_min = Tungsten::Date.parse_iso_offset_minutes(text)
      unless Tungsten::Date.packed_tz?(tz_min)
        raise ArgumentError,
              "Date timezone must be a 15-minute offset, or Amsterdam +00:20"
      end
      parts = ::Date._parse(text, false)
      year = parts[:year]
      month = parts[:mon]
      day = parts[:mday]
      hour = parts[:hour] || 0
      min = parts[:min] || 0
      sec = parts[:sec] || 0
      raise ArgumentError, "invalid datetime: #{text}" unless year && month && day
      if sec == 60
        unless Tungsten::Date.utc_leap_second?(year, month, day, hour, min, 60, tz_min)
          raise ArgumentError,
                "Second 60 is only valid as a UTC leap second (23:59:60 on a known leap-second date)"
        end
        @leap_second = true
        # Ruby DateTime cannot store second 60; keep 23:59:59 underneath and
        # report 60 from sec/second/to_s.
        @value = ::DateTime.new(year, month, day, hour, min, 59, Rational(tz_min, 24 * 60))
      else
        @leap_second = false
        @value = ::DateTime.parse(text)
      end
    end
  end
end
