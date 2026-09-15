# frozen_string_literal: true

require "date"

module Tungsten
  class Date < Literal
    # Civil days that existed historically but are invalid in proleptic
    # Gregorian. Keep in lockstep with runtime.c date_is_catchup_day.
    CatchupDate = Struct.new(:year, :month, :day) do
      DAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
      MONTH_NAMES = %w[January February March April May June July August September October November December].freeze

      def leap?
        (year % 4).zero? && ((year % 100) != 0 || (year % 400).zero?)
      end

      def wday
        ::Date.new(year, month, 1).wday.then { |wd| (wd + day - 1) % 7 }
      end

      def yday
        cum = [0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][month] + day
        cum += 1 if month > 2 && leap?
        cum
      end

      def cweek
        0
      end

      def strftime(fmt)
        fmt.to_s
           .gsub("%A", DAY_NAMES[wday] || "")
           .gsub("%B", MONTH_NAMES[month - 1] || "")
           .gsub("%Y", format("%04d", year))
           .gsub("%m", format("%02d", month))
           .gsub("%d", format("%02d", day))
           .gsub("%-d", day.to_s)
      end

      def to_s = strftime("%Y-%m-%d")
      def to_date = self
      def to_datetime
        ::DateTime.new(year, month, [day, 28].min)
      end

      def +(n)
        n = n.to_i
        # Feb 30 1712 + 1 → Mar 1 1712; century-leap Feb 29 + 1 → Mar 1.
        ::Date.new(year, month + 1, 1) + (n - 1)
      end

      def -(n)
        self.+(-n.to_i)
      end

      def <=>(other)
        [year, month, day] <=> [other.year, other.month, other.day]
      end
    end

    def self.catchup?(year, month, day)
      return true if year == 1712 && month == 2 && day == 30
      month == 2 && day == 29 && year >= 100 && year <= 1900 &&
        (year % 100).zero? && (year % 400) != 0
    end

    # IERS positive UTC leap-second dates (1972–2016). Packed Date can
    # store second 60; parse/new decide whether that second existed.
    # Keep in lockstep with runtime.c LEAP_SECOND_UTC.
    LEAP_SECOND_UTC = [
      [1972, 6, 30], [1972, 12, 31], [1973, 12, 31], [1974, 12, 31],
      [1975, 12, 31], [1976, 12, 31], [1977, 12, 31], [1978, 12, 31],
      [1979, 12, 31], [1981, 6, 30], [1982, 6, 30], [1983, 6, 30],
      [1985, 6, 30], [1987, 12, 31], [1989, 12, 31], [1990, 12, 31],
      [1992, 6, 30], [1993, 6, 30], [1994, 6, 30], [1995, 12, 31],
      [1997, 6, 30], [1998, 12, 31], [2005, 12, 31], [2008, 12, 31],
      [2012, 6, 30], [2015, 6, 30], [2016, 12, 31]
    ].freeze

    def self.packed_tz?(tz_min)
      tz = tz_min.to_i
      return true if tz == 20 # Amsterdam +00:20 (packed singleton)
      tz.between?(-960, 930) && (tz % 15).zero?
    end

    # tz_min is minutes east of UTC; omitted / Z / +00:00 is 0.
    # year=month=day=0 is the time-only 23:59:60 clock face.
    def self.utc_leap_second?(year, month, day, hour, min, sec, tz_min)
      return false unless sec.to_i == 60
      return false unless hour.to_i == 23 && min.to_i == 59
      return false unless tz_min.to_i.zero?
      y = year.to_i
      mo = month.to_i
      d = day.to_i
      return true if y.zero? && mo.zero? && d.zero?
      LEAP_SECOND_UTC.include?([y, mo, d])
    end

    # Offset from an ISO time/datetime suffix. Missing zone and Z are 0,
    # matching native w_date_parse. The last ±hh[:mm] after a clock is used
    # so negative years do not steal the sign.
    def self.parse_iso_offset_minutes(str)
      text = str.to_s
      return 0 if text.match?(/[Zz]\z/)
      if text =~ /[Tt]\d/
        suffix = text.split("T", 2).last
        if suffix =~ /([+\-])(\d{1,2})(?::?(\d{2}))?\z/
          sign = $1 == "-" ? -1 : 1
          return sign * ($2.to_i * 60 + ($3 || "0").to_i)
        end
        return 0
      end
      if text =~ /([+\-])(\d{1,2})(?::?(\d{2}))?\z/
        sign = $1 == "-" ? -1 : 1
        return sign * ($2.to_i * 60 + ($3 || "0").to_i)
      end
      0
    end

    def self.parse_civil(str)
      if str.to_s =~ /\A(-?\d+)-(\d+)-(\d+)/
        [$1.to_i, $2.to_i, $3.to_i]
      elsif str.to_s =~ /\A(-?\d+)-(\d{3})\z/
        ordinal_to_civil($1.to_i, $2.to_i)
      else
        d = ::Date.parse(str.to_s)
        [d.year, d.month, d.day]
      end
    end

    HIST_SKIP = [
      [1582, 10, 5, 14],
      [1752, 9, 3, 13],
      [1753, 2, 18, 28],
      [1844, 12, 31, 31],
      [1867, 10, 7, 17],
      [1918, 2, 1, 13],
      [1993, 8, 21, 21],
      [2011, 12, 30, 30]
    ].freeze
    HIST_REPEAT = [[1892, 7, 4]].freeze

    def self.month_length(year, month)
      return 30 if month == 2 && year == 1712
      return 29 if month == 2 && year >= 100 && year <= 1900 && (year % 100).zero? && (year % 400) != 0
      ::Date.new(year, month, -1).day
    rescue ArgumentError
      28
    end

    def self.civil_skipped?(year, month, day)
      HIST_SKIP.any? { |y, m, a, b| y == year && m == month && day >= a && day <= b }
    end

    def self.civil_repeat?(year, month, day)
      HIST_REPEAT.any? { |y, m, d| y == year && m == month && d == day }
    end

    def self.ordinal_len(year)
      n = ::Date.gregorian_leap?(year) ? 366 : 365
      n += 1 if year == 1712
      n += 1 if year >= 100 && year <= 1900 && (year % 100).zero? && (year % 400) != 0
      n += HIST_REPEAT.count { |y, _, _| y == year }
      HIST_SKIP.each { |y, _, a, b| n -= (b - a + 1) if y == year }
      n
    end

    def self.advance_civil(year, month, day)
      d = day + 1
      m = month
      loop do
        return nil if m < 1 || m > 12
        dim = month_length(year, m)
        if d > dim
          d = 1
          m += 1
          return nil if m > 12
        elsif civil_skipped?(year, m, d)
          d += 1
        else
          return [m, d]
        end
      end
    end

    def self.ordinal_to_civil(year, n)
      raise ArgumentError, "Date ordinal day is outside the requested year" if n < 1 || n > ordinal_len(year)
      m = 1
      d = 1
      held = false
      (1...n).each do
        if !held && civil_repeat?(year, m, d)
          held = true
        else
          held = false
          nxt = advance_civil(year, m, d)
          raise ArgumentError, "Date ordinal day is outside the requested year" unless nxt
          m, d = nxt
        end
      end
      [year, m, d]
    end

    def self.ordinal(year, number)
      y, m, d = ordinal_to_civil(year, number)
      new(y, m, d)
    end

    def self.make_value(year, month, day)
      if catchup?(year, month, day)
        CatchupDate.new(year, month, day)
      else
        ::Date.new(year, month, day)
      end
    end

    def self.parse(str)
      new(str)
    end

    def self.in(name)
      Calendar.at(name)
    end

    def initialize(*args)
      if args.length >= 3
        @value = self.class.make_value(args[0].to_i, args[1].to_i, args[2].to_i)
      elsif args.length == 1
        value = args[0]
        @value =
          case value
          when ::Date, CatchupDate then value
          else
            y, m, d = self.class.parse_civil(value.to_s)
            self.class.make_value(y, m, d)
          end
      else
        raise ArgumentError, "Date.new expects a string or year, month, day"
      end
    end

    def year = @value.year
    def month = @value.month
    def day = @value.day
    def quarter = ((month - 1) / 3) + 1

    def strftime(fmt)
      @value.strftime(fmt.to_s)
    end

    def to_s(fmt = nil)
      if fmt
        strftime(fmt)
      else
        "#{strftime("%Y-%m-%d")}T00:00:00Z"
      end
    end

    def +(other)
      case other
      when Duration
        base = calendar_date
        shifted = other.apply_months(base)
        if other.seconds.nil? || other.seconds == 0
          Date.new(shifted.is_a?(::Date) ? shifted : shifted.to_date)
        else
          date_or_datetime(shifted.to_datetime + Rational(other.seconds, 86400))
        end
      when Quantity
        if (months = calendar_months(other))
          Date.new(calendar_date >> months)
        else
          seconds = quantity_to_seconds(other)
          if seconds % 86400 == 0
            Date.new(calendar_date + (seconds / 86400).to_i)
          else
            date_or_datetime(calendar_date.to_datetime + Rational(seconds, 86400))
          end
        end
      when Integer
        Date.new(calendar_date + other)
      else
        Date.new(@value + other)
      end
    end

    def -(other)
      case other
      when Duration
        self + Duration.new(-other.months, -other.seconds)
      when Quantity
        if (months = calendar_months(other))
          Date.new(calendar_date >> -months)
        else
          seconds = quantity_to_seconds(other)
          if seconds % 86400 == 0
            Date.new(calendar_date - (seconds / 86400).to_i)
          else
            date_or_datetime(calendar_date.to_datetime - Rational(seconds, 86400))
          end
        end
      when Date
        (calendar_date - other.send(:calendar_date)).to_i
      when Integer
        Date.new(calendar_date - other)
      else
        Date.new(@value - other)
      end
    end

    def succ = Date.new(calendar_date + 1)
    def <=>(other) = calendar_date <=> (other.is_a?(Date) ? other.send(:calendar_date) : other)

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

    def calendar_date
      case @value
      when ::Date then @value
      when CatchupDate then ::Date.new(@value.year, @value.month, [@value.day, 28].min)
      else @value.to_date
      end
    end

    def date_or_datetime(result)
      if result == result.to_date
        Date.new(result.to_date)
      else
        DateTime.new(result)
      end
    end

    def calendar_months(qty)
      return nil unless qty.unit.components.size == 1
      name = qty.unit.components.keys.first
      n = qty.value
      case name
      when "mo", "month", "months" then n.to_i
      when "y", "year", "years" then (n * 12).to_i
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
