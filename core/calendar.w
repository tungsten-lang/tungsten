# Calendar — a named jurisdiction or zone for Date.in/1.
#
# Packed Date is a civil tuple plus a numeric offset. This object is the
# place: which days existed, and which offset a naive clock showed.
# Cutovers implemented here: Catholic 1582, Denmark–Norway 1700,
# Sweden 1700/1712/1753, Britain 1752, Russia 1918. Amsterdam supplies
# statutory +00:20 from 1937-05-01 through 1940-05-15.
#
# Skips, extras, and repeated midnights are one list. Local year length
# is era-leap ± extra ± repeat − skip count from that list.
+ Calendar
  # [key, year, month, day_lo, day_hi] — civil labels that never occurred.
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
  ]

  # [key, year, month, day_lo, day_hi] — civil labels that existed extra.
  EXTRA_ROWS = [
    ["sweden", 1712, 2, 30, 30]
  ]

  # [key, year, month, day] — same Y-M-D occupied two local midnights.
  REPEAT_ROWS = [
    ["samoa", 1892, 7, 4]
  ]

  # [key, year, month, day] — first civil day of Gregorian in this place.
  # Missing key ⇒ always Gregorian (Amsterdam, Samoa, Alaska, …).
  GREGORIAN_FROM = [
    ["sweden", 1753, 3, 1],
    ["denmark", 1700, 3, 1],
    ["britain", 1752, 9, 14],
    ["catholic", 1582, 10, 15],
    ["russia", 1918, 2, 14]
  ]

  # Inspector panels: [year, month, day_lo, day_hi, title, art lines].
  # Leap seconds and Julian century leaps are patterns, not rows.
  HISTORY_PANELS = [
    [1712, 2, 30, 30, "tillökningsdagen", "Charles XII added a second\nleap day (tillökningsdagen)\nafter a botched gradual\nGregorian conversion.\nYear had 367 days."],
    [1892, 7, 4, 4, "Samoa's two Independences", "Samoa kept the American day-\ncount by living Monday 4 July\ntwice. 1892-186 and 1892-187\nare the same civil date."],
    [1867, 10, 6, 6, "Alaska Purchase", "Sitka went to bed Friday 6 Oct\n(Julian) and woke Friday 18 Oct\n(Gregorian): calendar + date\nline. 1867-279 → 6th, 1867-280\n→ 18th — eleven labels skipped."],
    [1867, 10, 18, 18, "Alaska Purchase", "Sitka went to bed Friday 6 Oct\n(Julian) and woke Friday 18 Oct\n(Gregorian): calendar + date\nline. 1867-279 → 6th, 1867-280\n→ 18th — eleven labels skipped."],
    [1844, 12, 30, 30, "Clavería skipped New Year's Eve", "Governor Clavería jumped the\nPhilippines to the Asian date.\n30 Dec was followed by 1 Jan;\n31 Dec 1844 never existed there."],
    [1752, 9, 2, 2, "Chesterfield's Act", "Britain skipped 3–13 September.\n2 Sep was followed by 14 Sep.\nProleptic Gregorian still names\nthe missing days; ordinals here\ncount local midnights."],
    [1752, 9, 14, 14, "Chesterfield's Act", "Britain skipped 3–13 September.\n2 Sep was followed by 14 Sep.\nProleptic Gregorian still names\nthe missing days; ordinals here\ncount local midnights."],
    [1582, 10, 4, 4, "Inter gravissimas", "Gregory XIII: Thursday 4 Oct\nwas followed by Friday 15 Oct.\nTen days (5–14) never existed\nin Rome, Spain, Portugal.\nDate.in(\"Rome\") rejects them."],
    [1582, 10, 15, 15, "Inter gravissimas", "Gregory XIII: Thursday 4 Oct\nwas followed by Friday 15 Oct.\nTen days (5–14) never existed\nin Rome, Spain, Portugal.\nDate.in(\"Rome\") rejects them."],
    [1700, 2, 18, 18, "Denmark–Norway new style", "Denmark–Norway: Sunday 18 Feb\nwas followed by Monday 1 Mar.\nSkipped 19–29 Feb (11 days,\nincluding the Julian leap).\nDate.in(\"Denmark\") knows this."],
    [1753, 2, 17, 17, "Swedish new style", "Sweden: 17 Feb followed by\n1 Mar. Skipped 18–28 Feb\n(11 days), after the 1700–1712\nfalse start. Finland too."],
    [1918, 1, 31, 31, "Soviet calendar decree", "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
    [1918, 2, 1, 1, "Soviet calendar decree", "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
    [1918, 2, 14, 14, "Soviet calendar decree", "Sovnarkom: 31 Jan 1918 was\nfollowed by 14 Feb (13 days).\nCivil Russia is Gregorian;\nthe Orthodox church still\nuses Julian (Christmas 7 Jan)."],
    [2011, 12, 29, 29, "Samoa skipped a Friday", "Samoa skipped Friday 30 Dec to\njoin the Asian day-count.\n29 Dec was followed by 31 Dec."],
    [2011, 12, 31, 31, "Samoa skipped a Friday", "Samoa skipped Friday 30 Dec to\njoin the Asian day-count.\n29 Dec was followed by 31 Dec."]
  ]

  -> new(@key) ro

  -> .at(name)
    k = Calendar.key_for(name)
    if k == nil
      raise "Date.in: unknown calendar '" + name.to_s() + "'"
    Calendar.new(k)

  -> .key_for(name)
    s = name.to_s().downcase
    if s in ("sweden" "stockholm" "finland" "helsinki" "europe/stockholm" "europe/helsinki")
      return "sweden"
    if s in ("denmark" "norway" "copenhagen" "oslo" "europe/copenhagen" "europe/oslo" "denmark-norway")
      return "denmark"
    if s in ("britain" "england" "london" "uk" "gb" "great britain" "europe/london")
      return "britain"
    if s in ("rome" "italy" "spain" "portugal" "papal" "catholic" "europe/rome" "europe/madrid" "europe/lisbon")
      return "catholic"
    if s in ("amsterdam" "netherlands" "holland" "europe/amsterdam")
      return "amsterdam"
    if s in ("russia" "moscow" "petrograd" "leningrad" "europe/moscow" "ussr" "soviet")
      return "russia"
    if s in ("samoa" "apia" "pacific/apia")
      return "samoa"
    if s in ("alaska" "sitka" "america/anchorage")
      return "alaska"
    if s in ("kwajalein" "pacific/kwajalein")
      return "kwajalein"
    if s in ("philippines" "manila" "asia/manila")
      return "philippines"
    nil

  -> name
    @key

  -> to_s
    "Calendar(" + @key + ")"

  -> inspect
    to_s()

  -> parse(string)
    d = Date.parse(string)
    unless accepts?(d)
      raise "Date.in('" + @key + "'): " + d.to_s() + " is not a civil date in this jurisdiction"
    if @key == "amsterdam" && d.tz == 0 && amsterdam_amt?(d) && !explicit_offset?(string)
      d = Date.new(d.year, d.month, d.day, d.hour, d.minute, d.second, 20)
    wrap(d)

  # Z / ±hh:mm on the source is an offset, not "naive local". +00:00 and Z
  # must stay UTC even in the Amsterdam Time window.
  -> explicit_offset?(string)
    s = string.to_s()
    n = s.size()
    if n >= 1
      last = s.slice(n - 1, 1)
      if last == "Z" || last == "z"
        return true
    i = 0
    saw_t = false
    while i < n
      ch = s.slice(i, 1)
      if ch == "T" || ch == "t"
        saw_t = true
      if saw_t && (ch == "+" || ch == "-")
        return true
      i += 1
    false

  -> date(year, month = 1, day = 1, hour = 0, minute = 0, second = 0, tz = 0)
    if @key == "amsterdam" && tz == 0 && amsterdam_amt_civil(year, month, day)
      tz = 20
    d = Date.new(year, month, day, hour, minute, second, tz)
    unless accepts?(d)
      raise "Date.in('" + @key + "'): " + d.to_s() + " is not a civil date in this jurisdiction"
    wrap(d)

  -> wrap(d)
    CalendarDate.new(d, self)

  -> accepts?(d)
    accepts_ymd(d.year, d.month, d.day)

  -> offset_minutes(d)
    if @key == "amsterdam" && amsterdam_amt?(d)
      return 20
    d.tz

  # ---- cutovers (one skip / extra / repeat list) ----------------------

  -> amsterdam_amt?(d)
    amsterdam_amt_civil(d.year, d.month, d.day)

  # 1 May 1937 … 15 May 1940 inclusive (CET from 16 May 1940).
  -> amsterdam_amt_civil(y, m, day)
    if y > 1937 && y < 1940
      return true
    if y == 1937
      return m > 5 || (m == 5 && day >= 1)
    if y == 1940
      return m < 5 || (m == 5 && day <= 15)
    false

  -> row_for_key(rows)
    i = 0
    while i < rows.size()
      r = rows[i]
      if r[0] == @key
        return r
      i += 1
    nil

  -> gregorian_from_row
    row_for_key(GREGORIAN_FROM)

  -> gregorian_after(y, m, day, y0, m0, d0)
    y > y0 || (y == y0 && (m > m0 || (m == m0 && day >= d0)))

  -> gregorian_era?(y, m, day)
    row = gregorian_from_row()
    if row == nil
      return true
    gregorian_after(y, m, day, row[1], row[2], row[3])

  -> skipped?(y, m, day)
    i = 0
    rows = SKIP_ROWS
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == y && r[2] == m && day >= r[3] && day <= r[4]
        return true
      i += 1
    false

  -> extra_day?(y, m, day)
    i = 0
    rows = EXTRA_ROWS
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == y && r[2] == m && day >= r[3] && day <= r[4]
        return true
      i += 1
    false

  -> extra_hi(y, m)
    hi = 0
    i = 0
    rows = EXTRA_ROWS
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == y && r[2] == m && r[4] > hi
        hi = r[4]
      i += 1
    hi

  -> range_count(rows, year)
    n = 0
    i = 0
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == year
        n += r[4] - r[3] + 1
      i += 1
    n

  -> extra_count(year)
    range_count(EXTRA_ROWS, year)

  -> skip_count(year)
    range_count(SKIP_ROWS, year)

  -> repeat_count(year)
    n = 0
    i = 0
    rows = REPEAT_ROWS
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == year
        n += 1
      i += 1
    n

  # Cutover years keep the old-style February, so leap length comes from
  # the calendar that still named the skipped days.
  -> uses_julian_leaps?(year)
    row = gregorian_from_row()
    if row == nil
      return false
    year < row[1] || (year == row[1] && row[2] > 2)

  -> era_leap?(year)
    if uses_julian_leaps?(year)
      return year % 4 == 0
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0

  # Local midnights in `year`: era length, plus extras and repeats, minus
  # skipped labels. Derived from SKIP_ROWS / EXTRA_ROWS / REPEAT_ROWS.
  -> local_ordinal_len(year)
    len = 365
    if era_leap?(year)
      len = 366
    len + extra_count(year) + repeat_count(year) - skip_count(year)

  -> century_not_400(y)
    y % 100 == 0 && y % 400 != 0

  -> gregorian_day_ok(y, m, day)
    if extra_day?(y, m, day)
      return true
    if y == 1712 && m == 2 && day == 30
      return false
    if m == 2 && day == 29 && century_not_400(y)
      return false
    true

  -> julian_day_ok(y, m, day)
    if extra_day?(y, m, day)
      return true
    if y == 1712 && m == 2 && day == 30
      return false
    true

  -> gregorian_dim(y, m)
    if m == 2
      if (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        return 29
      return 28
    if m == 4 || m == 6 || m == 9 || m == 11
      return 30
    31

  -> julian_dim(y, m)
    if m == 2
      if y % 4 == 0
        return 29
      return 28
    gregorian_dim(y, m)

  -> julian_month?(y, m)
    row = gregorian_from_row()
    if row == nil
      return false
    y < row[1] || (y == row[1] && m < row[2])

  -> month_len(y, m)
    if julian_month?(y, m)
      dim = julian_dim(y, m)
    else
      dim = gregorian_dim(y, m)
    extra = extra_hi(y, m)
    if extra > dim
      return extra
    dim

  -> civil_ok(y, m, day)
    if m < 1 || m > 12 || day < 1
      return false
    if day > month_len(y, m)
      return false
    accepts_ymd(y, m, day)

  -> accepts_ymd(y, m, day)
    if extra_day?(y, m, day)
      return true
    if skipped?(y, m, day)
      return false
    if gregorian_era?(y, m, day)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  -> repeated_midnight?(y, m, day)
    i = 0
    rows = REPEAT_ROWS
    while i < rows.size()
      r = rows[i]
      if r[0] == @key && r[1] == y && r[2] == m && r[3] == day
        return true
      i += 1
    false

  -> .century_leap_day?(year, month, day)
    month == 2 && day == 29 && year >= 100 && year <= 1900 && year % 100 == 0 && year % 400 != 0

  -> .history_title(year, month, day, second = 0)
    if second == 60
      return "UTC leap second"
    if Calendar.century_leap_day?(year, month, day)
      return "Julian century leap"
    i = 0
    rows = HISTORY_PANELS
    while i < rows.size()
      r = rows[i]
      if r[0] == year && r[1] == month && day >= r[2] && day <= r[3]
        return r[4]
      i += 1
    ""

  -> .history_art(year, month, day, second = 0)
    if second == 60
      return [
        "IERS inserted a positive leap",
        "second: 23:59:60 UTC. Packed",
        "Date stores second 60; parse",
        "rejects any other :60. POSIX",
        "clocks often repeat 00:00:00."
      ]
    if Calendar.century_leap_day?(year, month, day)
      return [
        "Gregorian skips century years",
        "not divisible by 400.",
        "Julian jurisdictions still",
        "had 29 February — Britain",
        "until 1752, Russia until 1918."
      ]
    i = 0
    rows = HISTORY_PANELS
    while i < rows.size()
      r = rows[i]
      if r[0] == year && r[1] == month && day >= r[2] && day <= r[3]
        return r[5].split("\n")
      i += 1
    []

  # Local midnight number n in this jurisdiction. Repeats occupy two
  # consecutive n with the same civil Y-M-D; skips are omitted.
  -> ordinal(year, n)
    if !n.is_a?(Int)
      raise "Date.ordinal expects an integer ordinal day"
    len = local_ordinal_len(year)
    if n < 1 || n > len
      raise "Date ordinal day is outside the requested year"
    y = year
    m = 1
    d = 1
    unless civil_ok(y, m, d)
      raise "Date ordinal day is outside the requested year"
    i = 1
    held = false
    while i < n
      if !held && repeated_midnight?(y, m, d)
        held = true
      else
        held = false
        nxt = next_civil(y, m, d)
        if nxt[0] != year
          raise "Date ordinal day is outside the requested year"
        y = nxt[0]
        m = nxt[1]
        d = nxt[2]
      i += 1
    wrap(Date.new(y, m, d))

  -> next_civil(y, m, day)
    i = 0
    day += 1
    while i < 40
      if day > 31
        day = 1
        m += 1
        if m > 12
          m = 1
          y += 1
      if civil_ok(y, m, day)
        return [y, m, day]
      day += 1
      i += 1
    raise "Date.in('" + @key + "'): could not advance civil date"

  -> prev_civil(y, m, day)
    i = 0
    day -= 1
    while i < 40
      if day < 1
        m -= 1
        if m < 1
          m = 12
          y -= 1
        day = 31
      if civil_ok(y, m, day)
        return [y, m, day]
      day -= 1
      i += 1
    raise "Date.in('" + @key + "'): could not step back civil date"

  -> shift_days(d, n)
    y = d.year
    m = d.month
    day = d.day
    if n == 0
      return d
    while n > 0
      nxt = next_civil(y, m, day)
      y = nxt[0]
      m = nxt[1]
      day = nxt[2]
      n -= 1
    while n < 0
      prv = prev_civil(y, m, day)
      y = prv[0]
      m = prv[1]
      day = prv[2]
      n += 1
    Date.new(y, m, day, d.hour, d.minute, d.second, d.tz)

# A Date plus the jurisdiction that names its neighbors.
+ CalendarDate
  -> new(@civil, @calendar) ro

  -> year
    @civil.year
  -> month
    @civil.month
  -> day
    @civil.day
  -> hour
    @civil.hour
  -> minute
    @civil.minute
  -> second
    @civil.second
  -> tz
    @civil.tz

  -> to_s
    @civil.to_s()

  -> inspect
    @civil.to_s() + " in " + @calendar.name

  -> ==(other)
    if other.is_a?(CalendarDate)
      return @civil == other.civil
    @civil == other

  -> +(n)
    if n == 0
      return self
    if n.is_a?(Int)
      return CalendarDate.new(@calendar.shift_days(@civil, n), @calendar)
    raise "calendar date + expects an integer day count"

  -> -(n)
    if n == 0
      return self
    if n.is_a?(Int)
      return CalendarDate.new(@calendar.shift_days(@civil, -n), @calendar)
    if n.is_a?(CalendarDate)
      raise "calendar context day difference is not yet a packed integer"
    if n.is_a?(Date)
      raise "calendar context day difference is not yet a packed integer"
    raise "calendar date - expects an integer day count"
