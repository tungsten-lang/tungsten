# frozen_string_literal: true

require "time"

module Tungsten
  # Time-of-day literal: `12:30:45`, `09:30`, `12:30:45.123`, `12:30+05:30`, `12:30Z`.
  # Distinct from `DateTime` (no date) and `Duration` (not relative). Useful for
  # schedules, alarms, business-hours checks.
  #
  # Stored as: total seconds since midnight (Rational, for sub-second precision)
  # plus optional UTC offset in seconds (nil = naive, no timezone).
  class Time < Literal
    include Comparable

    attr_reader :seconds, :tz_offset

    SECONDS_PER_DAY = 86_400

    # value: a String like "12:30:45" or "12:30+05:30",
    #   or a Ruby ::Time (we extract HMS + offset).
    def initialize(value)
      case value
      when String
        parse_string(value)
      when ::Time
        sec_int = value.hour * 3600 + value.min * 60 + value.sec
        @seconds = Rational(sec_int) + Rational(value.subsec)
        @tz_offset = value.utc_offset
        @tz_offset = nil if value.zone.nil? && value.utc_offset.zero?
      when Numeric
        @seconds = Rational(value)
        @tz_offset = nil
      else
        raise ArgumentError, "cannot construct Time from #{value.class}"
      end
    end

    def hour    = (@seconds / 3600).to_i % 24
    def minute  = ((@seconds % 3600) / 60).to_i
    def second  = (@seconds % 60).to_i
    def fraction = @seconds - @seconds.to_i
    def naive?  = @tz_offset.nil?

    # Returns a new Time with the given UTC offset (in seconds, or :utc).
    # Doesn't shift the seconds-of-day — just attaches/changes the tz tag.
    def with_tz(offset)
      offset_secs = offset == :utc ? 0 : offset.to_i
      Time.allocate.tap do |t|
        t.instance_variable_set(:@seconds, @seconds)
        t.instance_variable_set(:@tz_offset, offset_secs)
      end
    end

    def +(other)
      case other
      when Duration
        raise DimensionError, "cannot add a Duration with nominal months to a Time" if other.months != 0
        shift_seconds(other.seconds)
      when Quantity
        ensure_time_quantity!(other, "add")
        shift_seconds(other.value * other.unit.factor)
      when Numeric
        shift_seconds(other)
      else
        raise DimensionError, "cannot add #{other.class} to Time"
      end
    end

    def -(other)
      case other
      when Time
        # Difference of two Times is a Quantity in seconds.
        diff = @seconds - other.seconds
        Quantity.new(diff, Units::CompoundUnit.new(
          dimension: Units::TIME, factor: 1, components: { "s" => 1 }
        ))
      when Duration
        raise DimensionError, "cannot subtract a Duration with nominal months from a Time" if other.months != 0
        shift_seconds(-other.seconds)
      when Quantity
        ensure_time_quantity!(other, "subtract")
        shift_seconds(-(other.value * other.unit.factor))
      when Numeric
        shift_seconds(-other)
      else
        raise DimensionError, "cannot subtract #{other.class} from Time"
      end
    end

    def <=>(other)
      return nil unless other.is_a?(Time)
      @seconds <=> other.seconds
    end

    def ==(other)
      other.is_a?(Time) && @seconds == other.seconds && @tz_offset == other.tz_offset
    end

    alias_method :eql?, :==

    def hash = [@seconds, @tz_offset].hash

    def to_s
      h = hour
      m = minute
      s = second
      frac = fraction
      base = "#{h.to_s.rjust(2, '0')}:#{m.to_s.rjust(2, '0')}:#{s.to_s.rjust(2, '0')}"
      base = "#{base}.#{format_fraction(frac)}" if frac > 0
      base + tz_suffix
    end

    def inspect = to_s

    private

    def shift_seconds(delta)
      total = @seconds + Rational(delta)
      total %= SECONDS_PER_DAY
      Time.allocate.tap do |t|
        t.instance_variable_set(:@seconds, total)
        t.instance_variable_set(:@tz_offset, @tz_offset)
      end
    end

    def parse_string(str)
      ruby_time = ::Time.parse("1970-01-01T#{str}")
      sec_int = ruby_time.hour * 3600 + ruby_time.min * 60 + ruby_time.sec
      @seconds = Rational(sec_int) + Rational(ruby_time.subsec)
      @tz_offset = if str =~ /[Zz]\z/
                     0
                   elsif str =~ /([+\-−])(\d\d):?(\d\d)?\z/
                     sign = ($1 == "+") ? 1 : -1
                     hh = $2.to_i
                     mm = ($3 || "0").to_i
                     sign * (hh * 3600 + mm * 60)
                   end
    end

    def format_fraction(frac)
      n = (frac * 1_000_000_000).round
      str = n.to_s.rjust(9, "0").sub(/0+\z/, "")
      str.empty? ? "0" : str
    end

    def tz_suffix
      return "" if @tz_offset.nil?
      return "Z" if @tz_offset.zero?
      sign = @tz_offset.negative? ? "-" : "+"
      abs = @tz_offset.abs
      hh = (abs / 3600).to_s.rjust(2, "0")
      mm = ((abs % 3600) / 60).to_s.rjust(2, "0")
      "#{sign}#{hh}:#{mm}"
    end

    def ensure_time_quantity!(qty, verb)
      return if qty.unit.dimension == Units::TIME
      raise DimensionError,
            "cannot #{verb} #{Units.dimension_name(qty.unit.dimension)} (#{qty.unit}) and a Time"
    end
  end
end
