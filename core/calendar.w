# Calendar — a named jurisdiction or zone for Date.in/1.
#
# Packed Date is a civil tuple plus a numeric offset. This object is the
# place: which days existed, and which offset a naive clock showed.
# Cutovers implemented here: Catholic 1582, Denmark–Norway 1700,
# Sweden 1700/1712/1753, Britain 1752, Russia 1918. Amsterdam supplies
# statutory +00:20 from 1937-05-01 through 1940-05-15.
+ Calendar
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
    if @key == "amsterdam" && d.tz == 0 && amsterdam_amt?(d)
      return Date.new(d.year, d.month, d.day, d.hour, d.minute, d.second, 20)
    d

  -> date(year, month = 1, day = 1, hour = 0, minute = 0, second = 0, tz = 0)
    if @key == "amsterdam" && tz == 0 && amsterdam_amt_civil(year, month, day)
      tz = 20
    d = Date.new(year, month, day, hour, minute, second, tz)
    unless accepts?(d)
      raise "Date.in('" + @key + "'): " + d.to_s() + " is not a civil date in this jurisdiction"
    d

  -> accepts?(d)
    y = d.year
    m = d.month
    day = d.day
    if @key == "sweden"
      return sweden_accepts(y, m, day)
    if @key == "denmark"
      return denmark_accepts(y, m, day)
    if @key == "britain"
      return britain_accepts(y, m, day)
    if @key == "catholic"
      return catholic_accepts(y, m, day)
    if @key == "amsterdam"
      return amsterdam_accepts(y, m, day)
    if @key == "russia"
      return russia_accepts(y, m, day)
    true

  -> offset_minutes(d)
    if @key == "amsterdam" && amsterdam_amt?(d)
      return 20
    d.tz

  # ---- cutovers -------------------------------------------------------

  # Sweden: skip 1700-02-29; 1712-02-30 extra; 1753-02-17 → 03-01
  # (skip 18–28 Feb). Julian 1712-03-01…1753-02-17; Gregorian after.
  -> sweden_accepts(y, m, day)
    if y == 1712 && m == 2 && day == 30
      return true
    if y == 1700 && m == 2 && day == 29
      return false
    if y == 1753 && m == 2 && day >= 18 && day <= 28
      return false
    if gregorian_after(y, m, day, 1753, 3, 1)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  # Denmark–Norway: 1700-02-18 → 03-01 (skip 19–29 Feb, including the
  # Julian leap day). Gregorian from 1700-03-01.
  -> denmark_accepts(y, m, day)
    if y == 1700 && m == 2 && day >= 19 && day <= 29
      return false
    if gregorian_after(y, m, day, 1700, 3, 1)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  # Britain: 1752-09-02 → 09-14 (skip 3–13 Sep). Gregorian from 1752-09-14.
  -> britain_accepts(y, m, day)
    if y == 1752 && m == 9 && day >= 3 && day <= 13
      return false
    if gregorian_after(y, m, day, 1752, 9, 14)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  # Papal / Catholic 1582: 10-04 → 10-15 (skip 5–14 Oct).
  -> catholic_accepts(y, m, day)
    if y == 1582 && m == 10 && day >= 5 && day <= 14
      return false
    if gregorian_after(y, m, day, 1582, 10, 15)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  # Russia: 1918-01-31 → 02-14 (skip 1–13 Feb). Julian until then
  # (including 1700/1800/1900-02-29). Civil Gregorian after; the
  # Orthodox church still uses Julian, which is Date.in("orthodox") later.
  -> russia_accepts(y, m, day)
    if y == 1918 && m == 2 && day >= 1 && day <= 13
      return false
    if gregorian_after(y, m, day, 1918, 2, 14)
      return gregorian_day_ok(y, m, day)
    julian_day_ok(y, m, day)

  # Amsterdam (Holland) was Gregorian well before 1700. Statutory
  # Amsterdam Time +00:20 is an offset, not a skipped day.
  -> amsterdam_accepts(y, m, day)
    gregorian_day_ok(y, m, day)

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

  -> gregorian_after(y, m, day, y0, m0, d0)
    y > y0 || (y == y0 && (m > m0 || (m == m0 && day >= d0)))

  -> gregorian_day_ok(y, m, day)
    if y == 1712 && m == 2 && day == 30
      return false
    if m == 2 && day == 29 && century_not_400(y)
      return false
    true

  -> julian_day_ok(y, m, day)
    if y == 1712 && m == 2 && day == 30
      return false
    true

  -> century_not_400(y)
    y % 100 == 0 && y % 400 != 0
