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
        return self if n.zero?
        raise Tungsten::Error, "calendar context required"
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
      parse_fields(str)[0, 3]
    end

    # ISO date, ordinal YYYY-DDD, or datetime with offset. Time and tz are
    # kept; offsets that are not a packed 15-minute step (or Amsterdam
    # +00:20) are rejected, matching native w_date_parse.
    def self.parse_fields(str)
      text = str.to_s
      if text =~ /\A(-?\d+)-(\d{3})\z/
        y, m, d = ordinal_to_civil($1.to_i, $2.to_i)
        return [y, m, d, 0, 0, 0, 0]
      end
      if text =~ /\A(-?\d+)-(\d+)-(\d+)(?:T(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|z|[+-]\d{1,2}(?::?\d{2})?)?)?\z/
        y = $1.to_i
        m = $2.to_i
        d = $3.to_i
        hour = ($4 || "0").to_i
        min = ($5 || "0").to_i
        sec = ($6 || "0").to_i
        tz = $4 ? parse_iso_offset_minutes(text) : 0
        return [y, m, d, hour, min, sec, tz]
      end
      d = ::Date.parse(text)
      [d.year, d.month, d.day, 0, 0, 0, 0]
    end

    def self.ordinal_len(year)
      ::Date.gregorian_leap?(year) ? 366 : 365
    end

    def self.ordinal_to_civil(year, n)
      raise Tungsten::Error, "Date ordinal day is outside the requested year" if n < 1 || n > ordinal_len(year)
      d = ::Date.ordinal(year, n)
      [d.year, d.month, d.day]
    end

    def self.ordinal(year, number)
      y = year.to_i
      raise Tungsten::Error, "Date year must be between -1024 and 3071" unless y.between?(-1024, 3071)
      yy, m, d = ordinal_to_civil(y, number.to_i)
      new(yy, m, d)
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

    def self.today
      t = ::Time.now
      new(t.year, t.month, t.day)
    end

    def self.in(name)
      Calendar.at(name)
    end

    def initialize(*args)
      if args.length == 1 && !args[0].is_a?(Integer)
        assign_from(args[0])
      elsif args.length.between?(1, 7)
        assign_civil(args[0], args[1] || 1, args[2] || 1, args[3] || 0, args[4] || 0, args[5] || 0, args[6] || 0)
      else
        raise ArgumentError, "Date.new expects a string or year, month, day"
      end
    end

    def year = @value.year
    def month = @value.month
    def day = @value.day
    def hour = @hour
    def minute = @minute
    def second = @second
    def tz = @tz
    def quarter = ((month - 1) / 3) + 1
    def unresolved? = self.class.catchup?(year, month, day)

    def strftime(fmt)
      @value.strftime(fmt.to_s)
    end

    def to_s(fmt = nil)
      if fmt
        strftime(fmt)
      else
        stamp = format("%04d-%02d-%02dT%02d:%02d:%02d", year, month, day, hour, minute, second)
        off = tz
        if off.zero?
          "#{stamp}Z"
        else
          sign = off.negative? ? "-" : "+"
          mag = off.abs
          format("%s%s%02d:%02d", stamp, sign, mag / 60, mag % 60)
        end
      end
    end

    def +(other)
      case other
      when Duration
        require_calendar unless duration_zero?(other)
        base = calendar_date
        shifted = other.apply_months(base)
        if other.seconds.nil? || other.seconds == 0
          with_clock(shifted.is_a?(::Date) ? shifted : shifted.to_date)
        else
          date_or_datetime(shifted.to_datetime + Rational(other.seconds, 86400))
        end
      when Quantity
        require_calendar unless quantity_zero?(other)
        if (months = calendar_months(other))
          with_clock(calendar_date >> months)
        else
          seconds = quantity_to_seconds(other)
          if seconds % 86400 == 0
            shift_civil_days((seconds / 86400).to_i)
          else
            date_or_datetime(calendar_date.to_datetime + Rational(seconds, 86400))
          end
        end
      when Integer
        shift_civil_days(other)
      else
        require_calendar
        Date.new(@value + other)
      end
    end

    def -(other)
      case other
      when Duration
        self + Duration.new(-other.months, -other.seconds)
      when Quantity
        if (months = calendar_months(other))
          require_calendar unless months.zero?
          with_clock(calendar_date >> -months)
        else
          seconds = quantity_to_seconds(other)
          if seconds % 86400 == 0
            shift_civil_days(-(seconds / 86400).to_i)
          else
            require_calendar unless seconds.zero?
            date_or_datetime(calendar_date.to_datetime - Rational(seconds, 86400))
          end
        end
      when Date
        require_calendar
        other.require_calendar
        (calendar_date - other.send(:calendar_date)).to_i
      when Integer
        shift_civil_days(-other)
      else
        require_calendar
        Date.new(@value - other)
      end
    end

    def succ = shift_civil_days(1)

    # Operators must not fall through Literal#method_missing onto the wrapped
    # ::Date, which refuses a Tungsten::Date as the other side.
    def <(other) = (self <=> other) < 0
    def <=(other) = (self <=> other) <= 0
    def >(other) = (self <=> other) > 0
    def >=(other) = (self <=> other) >= 0

    def <=>(other)
      mine = [year, month, day, hour, minute, second, tz]
      theirs =
        if other.is_a?(Date)
          [other.year, other.month, other.day, other.hour, other.minute, other.second, other.tz]
        else
          [other.year, other.month, other.day, 0, 0, 0, 0]
        end
      mine <=> theirs
    end

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

    def require_calendar
      raise Tungsten::Error, "calendar context required" if unresolved?
    end

    private

    def assign_from(value)
      case value
      when Date
        assign_civil(value.year, value.month, value.day, value.hour, value.minute, value.second, value.tz)
      when CatchupDate
        assign_civil(value.year, value.month, value.day, 0, 0, 0, 0)
      when ::DateTime
        tz_min = (value.offset * 24 * 60).to_i
        assign_civil(value.year, value.month, value.day, value.hour, value.min, value.sec, tz_min)
      when ::Date
        assign_civil(value.year, value.month, value.day, 0, 0, 0, 0)
      else
        assign_civil(*self.class.parse_fields(value.to_s))
      end
    end

    def assign_civil(year, month, day, hour = 0, minute = 0, second = 0, tz = 0)
      y = year.to_i
      m = month.to_i
      d = day.to_i
      h = hour.to_i
      min = minute.to_i
      sec = second.to_i
      tz_min = tz.to_i
      unless y.between?(-1024, 3071)
        raise Tungsten::Error, "Date year must be between -1024 and 3071"
      end
      unless d.between?(1, 31)
        raise Tungsten::Error, "Date day is outside the requested month"
      end
      unless h.between?(0, 23) && min.between?(0, 59) && sec.between?(0, 60)
        raise Tungsten::Error, "Date time must be within 00:00:00 and 23:59:60"
      end
      unless self.class.packed_tz?(tz_min)
        raise Tungsten::Error, "Date timezone must be a 15-minute offset, or Amsterdam +00:20"
      end
      if sec == 60 && !self.class.utc_leap_second?(y, m, d, h, min, sec, tz_min)
        raise Tungsten::Error,
              "Second 60 is only valid as a UTC leap second (23:59:60 on a known leap-second date)"
      end
      @value = self.class.make_value(y, m, d)
      @hour = h
      @minute = min
      @second = sec
      @tz = tz_min
    end

    def shift_civil_days(n)
      n = n.to_i
      return self if n.zero?

      require_calendar
      shifted = calendar_date + n
      with_clock(shifted)
    end

    def with_clock(civil)
      sec = second
      if sec == 60 &&
         !self.class.utc_leap_second?(civil.year, civil.month, civil.day, hour, minute, 60, tz)
        sec = 59
      end
      Date.new(civil.year, civil.month, civil.day, hour, minute, sec, tz)
    end

    def duration_zero?(other)
      other.months.to_i.zero? && (other.seconds.nil? || other.seconds == 0)
    end

    def quantity_zero?(other)
      if (months = calendar_months(other))
        months.zero?
      else
        quantity_to_seconds(other).zero?
      end
    end

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
