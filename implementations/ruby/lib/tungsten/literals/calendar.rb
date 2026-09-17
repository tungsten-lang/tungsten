# frozen_string_literal: true

module Tungsten
  class Calendar
    attr_reader :key
    alias name key

    KEYS = {
      "sweden" => "sweden", "stockholm" => "sweden", "finland" => "sweden",
      "helsinki" => "sweden", "europe/stockholm" => "sweden", "europe/helsinki" => "sweden",
      "denmark" => "denmark", "norway" => "denmark", "copenhagen" => "denmark",
      "oslo" => "denmark", "europe/copenhagen" => "denmark", "europe/oslo" => "denmark",
      "denmark-norway" => "denmark",
      "britain" => "britain", "england" => "britain", "london" => "britain",
      "uk" => "britain", "gb" => "britain", "great britain" => "britain",
      "europe/london" => "britain",
      "rome" => "catholic", "italy" => "catholic", "spain" => "catholic",
      "portugal" => "catholic", "papal" => "catholic", "catholic" => "catholic",
      "europe/rome" => "catholic", "europe/madrid" => "catholic", "europe/lisbon" => "catholic",
      "amsterdam" => "amsterdam", "netherlands" => "amsterdam", "holland" => "amsterdam",
      "europe/amsterdam" => "amsterdam",
      "russia" => "russia", "moscow" => "russia", "petrograd" => "russia",
      "leningrad" => "russia", "europe/moscow" => "russia", "ussr" => "russia",
      "soviet" => "russia",
      "samoa" => "samoa", "apia" => "samoa", "pacific/apia" => "samoa",
      "alaska" => "alaska", "sitka" => "alaska", "america/anchorage" => "alaska",
      "kwajalein" => "kwajalein", "pacific/kwajalein" => "kwajalein",
      "philippines" => "philippines", "manila" => "philippines", "asia/manila" => "philippines"
    }.freeze

    # Keep in lockstep with core/calendar.w. Local year length is
    # era-leap ± extra ± repeat − skip count from these rows.
    SKIP_ROWS = [
      ["sweden", 1700, 2, 29, 29],
      ["sweden", 1753, 2, 18, 28],
      ["denmark", 1700, 2, 19, 29],
      ["britain", 1752, 9, 3, 13],
      ["catholic", 1582, 10, 5, 14],
      ["russia", 1918, 2, 1, 13],
      ["samoa", 2011, 12, 30, 30],
      ["alaska", 1867, 10, 7, 17],
      ["kwajalein", 1993, 8, 21, 21],
      ["philippines", 1844, 12, 31, 31]
    ].freeze

    EXTRA_ROWS = [
      ["sweden", 1712, 2, 30, 30]
    ].freeze

    REPEAT_ROWS = [
      ["samoa", 1892, 7, 4]
    ].freeze

    GREGORIAN_FROM = {
      "sweden" => [1753, 3, 1],
      "denmark" => [1700, 3, 1],
      "britain" => [1752, 9, 14],
      "catholic" => [1582, 10, 15],
      "russia" => [1918, 2, 14]
    }.freeze

    LEAP_SECOND_ART = [
      "IERS inserted a positive leap",
      "second: 23:59:60 UTC. Packed",
      "Date stores second 60; parse",
      "rejects any other :60. POSIX",
      "clocks often repeat 00:00:00."
    ].freeze

    CENTURY_LEAP_ART = [
      "Gregorian skips century years",
      "not divisible by 400.",
      "Julian jurisdictions still",
      "had 29 February — Britain",
      "until 1752, Russia until 1918."
    ].freeze

    HISTORY_PANELS = [
      [1712, 2, 30, 30, "tillökningsdagen",
       "Charles XII added a second\nleap day (tillökningsdagen)\nafter a botched gradual\nGregorian conversion.\nYear had 367 days."],
      [1892, 7, 4, 4, "Samoa's two Independences",
       "Samoa kept the American day-\ncount by living Monday 4 July\ntwice. 1892-186 and 1892-187\nare the same civil date."],
      [1867, 10, 6, 6, "Alaska Purchase",
       "Sitka went to bed Friday 6 Oct\n(Julian) and woke Friday 18 Oct\n(Gregorian): calendar + date\nline. 1867-279 → 6th, 1867-280\n→ 18th — eleven labels skipped."],
      [1867, 10, 18, 18, "Alaska Purchase",
       "Sitka went to bed Friday 6 Oct\n(Julian) and woke Friday 18 Oct\n(Gregorian): calendar + date\nline. 1867-279 → 6th, 1867-280\n→ 18th — eleven labels skipped."],
      [1844, 12, 30, 30, "Clavería skipped New Year's Eve",
       "Governor Clavería jumped the\nPhilippines to the Asian date.\n30 Dec was followed by 1 Jan;\n31 Dec 1844 never existed there."],
      [1752, 9, 2, 2, "Chesterfield's Act",
       "Britain skipped 3–13 September.\n2 Sep was followed by 14 Sep.\nProleptic Gregorian still names\nthe missing days; ordinals here\ncount local midnights."],
      [1752, 9, 14, 14, "Chesterfield's Act",
       "Britain skipped 3–13 September.\n2 Sep was followed by 14 Sep.\nProleptic Gregorian still names\nthe missing days; ordinals here\ncount local midnights."],
      [1582, 10, 4, 4, "Inter gravissimas",
       "Gregory XIII: Thursday 4 Oct\nwas followed by Friday 15 Oct.\nTen days (5–14) never existed\nin Rome, Spain, Portugal.\nDate.in(\"Rome\") rejects them."],
      [1582, 10, 15, 15, "Inter gravissimas",
       "Gregory XIII: Thursday 4 Oct\nwas followed by Friday 15 Oct.\nTen days (5–14) never existed\nin Rome, Spain, Portugal.\nDate.in(\"Rome\") rejects them."],
      [1700, 2, 18, 18, "Denmark–Norway new style",
       "Denmark–Norway: Sunday 18 Feb\nwas followed by Monday 1 Mar.\nSkipped 19–29 Feb (11 days,\nincluding the Julian leap).\nDate.in(\"Denmark\") knows this."],
      [1753, 2, 17, 17, "Swedish new style",
       "Sweden: 17 Feb followed by\n1 Mar. Skipped 18–28 Feb\n(11 days), after the 1700–1712\nfalse start. Finland too."],
      [1918, 1, 31, 31, "Soviet calendar decree",
       "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
      [1918, 2, 1, 1, "Soviet calendar decree",
       "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
      [1918, 2, 14, 14, "Soviet calendar decree",
       "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
      [2011, 12, 29, 29, "Samoa skipped a Friday",
       "Samoa skipped Friday 30 Dec to\njoin the Asian day-count.\n29 Dec was followed by 31 Dec."],
      [2011, 12, 31, 31, "Samoa skipped a Friday",
       "Samoa skipped Friday 30 Dec to\njoin the Asian day-count.\n29 Dec was followed by 31 Dec."]
    ].freeze

    def self.at(name)
      key = KEYS[name.to_s.downcase]
      raise ArgumentError, "Date.in: unknown calendar '#{name}'" unless key
      new(key)
    end

    def self.century_leap_day?(year, month, day)
      month == 2 && day == 29 && year >= 100 && year <= 1900 &&
        (year % 100).zero? && (year % 400) != 0
    end

    def self.history_panel(year, month, day)
      HISTORY_PANELS.find { |y, m, lo, hi,| y == year && m == month && day.between?(lo, hi) }
    end

    def self.history_title(year, month, day, second = 0)
      return "UTC leap second" if second.to_i == 60
      return "Julian century leap" if century_leap_day?(year, month, day)
      panel = history_panel(year, month, day)
      panel ? panel[4] : ""
    end

    def self.history_art(year, month, day, second = 0)
      return LEAP_SECOND_ART if second.to_i == 60
      return CENTURY_LEAP_ART if century_leap_day?(year, month, day)
      panel = history_panel(year, month, day)
      panel ? panel[5].split("\n") : []
    end

    def initialize(key)
      @key = key
    end

    def to_s = "Calendar(#{@key})"
    alias inspect to_s

    def parse(string)
      d = Date.parse(string)
      raise ArgumentError, "Date.in('#{@key}'): #{d} is not a civil date in this jurisdiction" unless accepts?(d)
      if @key == "amsterdam" && d.respond_to?(:tz) && d.tz.to_i.zero? &&
         amsterdam_amt?(d) && !explicit_offset?(string)
        return Date.new(d.year, d.month, d.day, d.hour, d.minute, d.second, 20)
      end
      d
    end

    def explicit_offset?(string)
      s = string.to_s
      return true if s.end_with?("Z", "z")
      rest = s.split(/t/i, 2)[1]
      rest&.include?("+") || rest&.include?("-")
    end

    def amsterdam_amt?(d)
      y, m, day = d.year, d.month, d.day
      return true if y > 1937 && y < 1940
      return m > 5 || (m == 5 && day >= 1) if y == 1937
      return m < 5 || (m == 5 && day <= 15) if y == 1940
      false
    end

    def accepts?(d)
      accepts_ymd(d.year, d.month, d.day)
    end

    def local_ordinal_len(year)
      len = era_leap?(year) ? 366 : 365
      len + extra_count(year) + repeat_count(year) - skip_count(year)
    end

    def ordinal(year, n)
      raise ArgumentError, "Date.ordinal expects an integer ordinal day" unless n.respond_to?(:to_i)
      n = n.to_i
      len = local_ordinal_len(year)
      raise ArgumentError, "Date ordinal day is outside the requested year" if n < 1 || n > len
      y = year
      m = 1
      d = 1
      raise ArgumentError, "Date ordinal day is outside the requested year" unless civil_ok?(y, m, d)
      i = 1
      held = false
      while i < n
        if !held && repeated_midnight?(y, m, d)
          held = true
        else
          held = false
          y, m, d = next_civil(y, m, d)
          raise ArgumentError, "Date ordinal day is outside the requested year" if y != year
        end
        i += 1
      end
      Date.new(y, m, d)
    end

    private

    def gregorian_from
      GREGORIAN_FROM[@key]
    end

    def gregorian_after(y, m, day, y0, m0, d0)
      y > y0 || (y == y0 && (m > m0 || (m == m0 && day >= d0)))
    end

    def gregorian_era?(y, m, day)
      row = gregorian_from
      return true unless row
      gregorian_after(y, m, day, *row)
    end

    def skipped?(y, m, day)
      SKIP_ROWS.any? { |key, yy, mm, lo, hi| key == @key && yy == y && mm == m && day.between?(lo, hi) }
    end

    def extra_day?(y, m, day)
      EXTRA_ROWS.any? { |key, yy, mm, lo, hi| key == @key && yy == y && mm == m && day.between?(lo, hi) }
    end

    def extra_count(year)
      EXTRA_ROWS.sum { |key, yy, _m, lo, hi| key == @key && yy == year ? hi - lo + 1 : 0 }
    end

    def skip_count(year)
      SKIP_ROWS.sum { |key, yy, _m, lo, hi| key == @key && yy == year ? hi - lo + 1 : 0 }
    end

    def repeat_count(year)
      REPEAT_ROWS.count { |key, yy,| key == @key && yy == year }
    end

    def uses_julian_leaps?(year)
      row = gregorian_from
      return false unless row
      year < row[0] || (year == row[0] && row[1] > 2)
    end

    def era_leap?(year)
      if uses_julian_leaps?(year)
        (year % 4).zero?
      else
        (year % 4).zero? && ((year % 100) != 0 || (year % 400).zero?)
      end
    end

    def gregorian_day_ok(y, m, day)
      return true if extra_day?(y, m, day)
      return false if y == 1712 && m == 2 && day == 30
      return false if m == 2 && day == 29 && (y % 100).zero? && (y % 400) != 0
      true
    end

    def julian_day_ok(y, m, day)
      return true if extra_day?(y, m, day)
      !(y == 1712 && m == 2 && day == 30)
    end

    def accepts_ymd(y, m, day)
      return true if extra_day?(y, m, day)
      return false if skipped?(y, m, day)
      gregorian_era?(y, m, day) ? gregorian_day_ok(y, m, day) : julian_day_ok(y, m, day)
    end

    def repeated_midnight?(y, m, day)
      REPEAT_ROWS.any? { |key, yy, mm, d| key == @key && yy == y && mm == m && d == day }
    end

    def julian_month?(y, m)
      row = gregorian_from
      return false unless row
      y < row[0] || (y == row[0] && m < row[1])
    end

    def gregorian_dim(y, m)
      return ::Date.gregorian_leap?(y) ? 29 : 28 if m == 2
      [4, 6, 9, 11].include?(m) ? 30 : 31
    end

    def julian_dim(y, m)
      return (y % 4).zero? ? 29 : 28 if m == 2
      gregorian_dim(y, m)
    end

    def extra_hi(y, m)
      EXTRA_ROWS.select { |key, yy, mm,| key == @key && yy == y && mm == m }.map { |row| row[4] }.max || 0
    end

    def month_len(y, m)
      dim = julian_month?(y, m) ? julian_dim(y, m) : gregorian_dim(y, m)
      extra = extra_hi(y, m)
      extra > dim ? extra : dim
    end

    def civil_ok?(y, m, day)
      m.between?(1, 12) && day >= 1 && day <= month_len(y, m) && accepts_ymd(y, m, day)
    end

    def next_civil(y, m, day)
      40.times do
        day += 1
        if day > 31
          day = 1
          m += 1
          if m > 12
            m = 1
            y += 1
          end
        end
        return [y, m, day] if civil_ok?(y, m, day)
      end
      raise ArgumentError, "Date.in('#{@key}'): could not advance civil date"
    end
  end
end
