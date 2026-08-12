# Date — validated packed proleptic-Gregorian calendar and datetime values.
#
# Years are limited by the WValue representation to -2048..2047. Constructors,
# ISO/ordinal/Julian factories, and period boundaries raise rather than wrapping
# when a requested result cannot be represented.
+ Date
  is Enumerable

  DAYS        = %w[Sun Mon Tue Wed Thu Fri Sat]
  DAY_NAMES   = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]

  MONTHS      = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
  MONTH_NAMES = %w[January February March April May June July August September October November December]

  FORMATS = {ctime: "%a %b %e 00:00:00 %Y", http: "%a, %d, %b, %Y 00:00:00 GMT", iso8601: "%Y-%m-%d", rfc3339: "%Y-%m-%dT00:00:00+00:00", rfc2822: "%a, %-d %b %Y 00:00:00 +0000", rfc822: "%a, %-d %b %Y 00:00:00 +0000"}

  -> .parse(string)
    ccall("w_date_parse", string)

  # Construct the packed scalar directly. The runtime leaf validates the
  # representation bounds and calendar fields before packing; defaults keep
  # the common Date.new(year, month, day) surface concise while still allowing
  # the datetime fields represented by Date literals.
  -> .new(year, month = 1, day = 1, hour = 0, minute = 0, second = 0, tz = 0)
    if year == nil
      raise "Date.new expects one to seven arguments"
    ccall("w_date_new_w", year, month, day, hour, minute, second, tz)

  # Proleptic-Gregorian date from a Julian day number.
  -> .julian(number)
    if !number.is_a?(Int)
      raise "Date.julian expects an integer Julian day number"
    a = number + 32_044
    b = (4 * a + 3) / 146_097
    c = a - (146_097 * b) / 4
    d = (4 * c + 3) / 1_461
    e = c - (1_461 * d) / 4
    m = (5 * e + 2) / 153
    day = e - (153 * m + 2) / 5 + 1
    month = m + 3 - 12 * (m / 10)
    year = 100 * b + d - 4_800 + m / 10
    Date.new(year, month, day)

  # Proleptic-Gregorian ordinal day, 1..365/366.
  -> .ordinal(year, number)
    if !number.is_a?(Int)
      raise "Date.ordinal expects an integer ordinal day"
    first = Date.new(year, 1, 1)
    if number < 1 || number > first.days_in_year
      raise "Date.ordinal day is outside the requested year"
    first + (number - 1)

  # ISO week date: Monday=1, Sunday=7; week 1 contains January 4.
  -> .commercial(year, week, day)
    if !week.is_a?(Int) || !day.is_a?(Int)
      raise "Date.commercial expects integer week and day values"
    if day < 1 || day > 7
      raise "Date.commercial day must be between 1 and 7"
    weeks = Date.new(year, 12, 28).cweek
    if week < 1 || week > weeks
      raise "Date.commercial week is outside the requested ISO year"
    jan4 = Date.new(year, 1, 4)
    first_monday = jan4 - (jan4.cwday - 1)
    first_monday + (week - 1) * 7 + (day - 1)

  # Local civil dates. The clock read remains a narrow runtime primitive;
  # tomorrow's calendar arithmetic uses the ordinary Date operator.
  -> .today
    ccall("w_date_today")

  -> .tomorrow
    Date.today + 1

  # Date is packed directly into a WValue. `$value` exposes the raw bits to
  # compiled Tungsten, keeping these leaf accessors and calendar calculations
  # allocation-free and equivalent to their former runtime.c IC handlers.
  -> day
    ($value >> 24) & 0x1F

  -> week
    cweek

  -> month
    ($value >> 29) & 0xF

  -> quarter
    ((($value >> 29) & 0xF) - 1) / 3 + 1

  -> year
    raw_year = (($value >> 33) & 0xFFF) ## i64
    raw_year >= 0x800 ? raw_year - 0x1000 : raw_year

  -> hour
    ($value >> 19) & 0x1F

  -> minute
    ($value >> 13) & 0x3F

  -> second
    ($value >> 7) & 0x3F

  -> tz
    raw_tz = ($value & 0x7F) ## i64
    quarters = raw_tz ## i64
    if quarters >= 0x40
      quarters -= 0x80
    quarters * 15

  # Period values are their starting Gregorian year, making decade_abbr
  # naturally produce strings such as "2020s". Normalize negative remainders
  # explicitly so BCE periods use mathematical floor rather than truncation.
  -> decade
    remainder = year % 10
    remainder += 10 if remainder < 0
    year - remainder

  -> century
    remainder = year % 100
    remainder += 100 if remainder < 0
    year - remainder

  -> millenium
    remainder = year % 1_000
    remainder += 1_000 if remainder < 0
    year - remainder

  # Correctly spelled alias alongside the historical Tungsten API spelling.
  -> millennium
    millenium

  -> asctime
    self.ctime()

  -> ctime
    self.strftime(FORMATS[:ctime])

  -> cwday
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    d = (($value >> 24) & 0x1F) ## i64
    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    jdn = (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64
    (((jdn % 7) + 7) % 7 + 1) ## i64

  -> cweek
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    d = (($value >> 24) & 0x1F) ## i64

    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    jdn = (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64
    iso_wday = (((jdn % 7) + 7) % 7 + 1) ## i64

    yday = d ## i64
    if m > 1
      yday += 31
    if m > 2
      leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      yday += leap ? 29 : 28
    if m > 3
      yday += 31
    if m > 4
      yday += 30
    if m > 5
      yday += 31
    if m > 6
      yday += 30
    if m > 7
      yday += 31
    if m > 8
      yday += 31
    if m > 9
      yday += 30
    if m > 10
      yday += 31
    if m > 11
      yday += 30

    week = ((yday - iso_wday + 10) / 7) ## i64
    week_year = y ## i64
    if week < 1
      week_year = y - 1
    elsif week > 52
      week_year = y

    jan_yy = (week_year + 4799) ## i64
    jan_jdn = (307 + 365 * jan_yy + jan_yy / 4 - jan_yy / 100 + jan_yy / 400 - 32045) ## i64
    jan_wday = (((jan_jdn % 7) + 7) % 7 + 1) ## i64
    week_year_leap = (week_year % 4 == 0 && week_year % 100 != 0) || week_year % 400 == 0
    weeks = 52 ## i64
    if jan_wday == 4 || (week_year_leap && jan_wday == 3)
      weeks = 53

    if week < 1
      return weeks
    if week > weeks
      return 1
    week

  -> cwyear
    week = cweek
    m = (($value >> 29) & 0xF) ## i64
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    if m == 1 && week >= 52
      return y - 1
    if m == 12 && week == 1
      return y + 1
    y

  -> wday
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    d = (($value >> 24) & 0x1F) ## i64
    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    jdn = (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64
    ((((jdn + 1) % 7) + 7) % 7) ## i64

  -> day_abbr
    DAYS[day_of_week]

  -> day_name
    DAY_NAMES[day_of_week]

  -> month_abbr
    MONTHS[month - 1]

  -> month_name
    MONTH_NAMES[month - 1]

  -> quarter_abbr
    "Q[quarter]"

  -> year_with_quarter
    "[year]Q[quarter]"

  -> decade_abbr
    "[decade]s"

  -> day_of_week
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    d = (($value >> 24) & 0x1F) ## i64
    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    jdn = (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64
    ((((jdn + 1) % 7) + 7) % 7) ## i64

  -> day_of_month
    ($value >> 24) & 0x1F

  -> day_of_quarter
    month_in_quarter = (month - 1) % 3
    result = day
    if month_in_quarter >= 1
      first_month = month - month_in_quarter
      if first_month == 2
        result += leap? ? 29 : 28
      else
        result += 31 - ((0xA50 >> first_month) & 1)
    if month_in_quarter >= 2
      second_month = month - 1
      if second_month == 2
        result += leap? ? 29 : 28
      else
        result += 31 - ((0xA50 >> second_month) & 1)
    result

  -> day_of_year
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    yday = (($value >> 24) & 0x1F) ## i64
    if m > 1
      yday += 31
    if m > 2
      leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      yday += leap ? 29 : 28
    if m > 3
      yday += 31
    if m > 4
      yday += 30
    if m > 5
      yday += 31
    if m > 6
      yday += 30
    if m > 7
      yday += 31
    if m > 8
      yday += 31
    if m > 9
      yday += 30
    if m > 10
      yday += 31
    if m > 11
      yday += 30
    yday

  -> yday
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    yday = (($value >> 24) & 0x1F) ## i64
    if m > 1
      yday += 31
    if m > 2
      leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      yday += leap ? 29 : 28
    if m > 3
      yday += 31
    if m > 4
      yday += 30
    if m > 5
      yday += 31
    if m > 6
      yday += 30
    if m > 7
      yday += 31
    if m > 8
      yday += 31
    if m > 9
      yday += 30
    if m > 10
      yday += 31
    if m > 11
      yday += 30
    yday

  -> days_in_month
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    if m == 2
      leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
      return leap ? 29 : 28
    # Bits 4, 6, 9, and 11 mark the four 30-day months. This avoids a
    # four-way short-circuit chain on the hot non-February path.
    31 - ((0xA50 >> m) & 1)

  -> days_in_year
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    leap ? 366 : 365

  -> first_of_week
    self - (cwday - 1)

  -> first_of_month
    Date.new(year, month, 1, hour, minute, second, tz)

  -> first_of_quarter
    first_month = (quarter - 1) * 3 + 1
    Date.new(year, first_month, 1, hour, minute, second, tz)

  -> first_of_year
    Date.new(year, 1, 1, hour, minute, second, tz)

  -> first_of_decade
    Date.new(decade, 1, 1, hour, minute, second, tz)

  -> first_of_century
    Date.new(century, 1, 1, hour, minute, second, tz)

  -> first_of_millenium
    Date.new(millenium, 1, 1, hour, minute, second, tz)

  -> first_of_millennium
    first_of_millenium

  -> last_of_week
    self + (7 - cwday)

  -> last_of_month
    Date.new(year, month, days_in_month, hour, minute, second, tz)

  -> last_of_quarter
    last_month = quarter * 3
    month_end = Date.new(year, last_month, 1, hour, minute, second, tz)
    Date.new(year, last_month, month_end.days_in_month, hour, minute, second, tz)

  -> last_of_year
    Date.new(year, 12, 31, hour, minute, second, tz)

  -> last_of_decade
    Date.new(decade + 9, 12, 31, hour, minute, second, tz)

  -> last_of_century
    Date.new(century + 99, 12, 31, hour, minute, second, tz)

  -> last_of_millenium
    Date.new(millenium + 999, 12, 31, hour, minute, second, tz)

  -> last_of_millennium
    last_of_millenium

  -> leap_year?
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

  -> leap?
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    (y % 4 == 0 && y % 100 != 0) || y % 400 == 0

  -> jd
    y = (($value >> 33) & 0xFFF) ## i64
    if y >= 0x800
      y -= 0x1000
    m = (($value >> 29) & 0xF) ## i64
    d = (($value >> 24) & 0x1F) ## i64
    a = ((14 - m) / 12) ## i64
    yy = (y + 4800 - a) ## i64
    mm = (m + 12 * a - 3) ## i64
    (d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045) ## i64

  -> to_s

  alias_method :to_s/1, :strftime/1

  # Formats _date_ according to the directives in the given format string
  #
  # Directives begin with a percent character. All other text will be included in the output.
  #
  #     %<flags><width><modifier><conversion>
  #
  # **Flags:**
  #
  #     - Do not pad numerical output
  #     _ Pad with spaces
  #     0 Pad with zeros
  #     ^ Upcase the result
  #     # Change case
  #     : Use colons for %z
  #
  # _width_ specifies the minimum width.
  #
  # The valid values for _modifier_ are "E", "O", ":", "::", and ":::".
  #
  # Format directives:
  #
  #     # Date (Year, Month, Day):
  #
  #     %Y - Year with century (can be negative, 4 digits at least)
  #          -0001, 0000, 0001, 2015, 15000, etc.
  #     %C - year / 100 (floored, 20 in 2009)
  #     %y - year % 100 (00..99)
  #
  #     %m - Month of year, zero-padded (01..12)
  #          %_m space-padded ( 1..12)
  #          %-m not-padded (1..12)
  #     %B - The full month name (January)
  #          %^B uppercased (JANUARY)
  #     %b - The abbreviated month name (Jan)
  #          %^b uppercased (JAN)
  #     %h - Equivalent to %b
  #
  #     %d - Day of month, zero-padded (01..31)
  #          %-d not-padded (1..31)
  #     %e - Day of month, blank-padded ( 1..31)
  #
  #     %j - Day of year (001..366)
  #
  #     # Weekday:
  #     %A - The full weekday name (Sunday)
  #          %^A uppercased (SUNDAY)
  #     %a - The abbreviated weekday name (Sun)
  #          %^a uppercased (SUN)
  #     %u - Day of week (Monday is 1, 1..7)
  #     %w - Day of week (Sunday is 0, 0..6)
  #
  #     # ISO 8601 week-based year and week number:
  #     # The week 1 of YYYY starts with a Monday and includes YYYY-01-04.
  #     # The days in the year before the first week are in the last week of the previous year.
  #     %G - The week-based year
  #     %g - The last 2 digits of the week-based year (00..99)
  #     %V - Week number of the week-based year (01..53)
  #
  #     # Week number:
  #     # The week 1 of YYYY starts with a Sunday or Monday according to %U or %W).
  #     # The days in the year before the first week are in week 0.
  #     %U - Week number of the year. The week starts with Sunday. (00..53)
  #     %W - Week number of the year. The week starts with Monday. (00..53)
  #
  #     # Literal string:
  #     %n - Newline character (\n)
  #     %t - Tab character (\t)
  #     %% - Literal percent character
  #
  #     # Combination
  #     %D - Date (%m/%d/%y)
  #     %F - The ISO 8601 date format (%Y-%m-%d)
  #     %v - VMS date (%e-%b-%Y)
  #     %x - Same as %D
  #
  # This method is similar to the strftime() function defined in ISO C or POSIX.
  # Several directives are locale _dependent_ in the function. However this method is locale _independent_.
  #
  #     # Various ISO 8601 formats
  #     %Y%m%d       # 20071119   Calendar date (basic)
  #     %F           # 2017-11-19 Calendar date (extended)
  #     %Y-%m        # 2007-11    Calendar date, reduced accuracy, specific month
  #     %Y           # 2007       Calendar date, reduced accuracy, specific year
  #     %C           # 20         Calendar date, reduced accuracy, specific century
  #     %Y%j         # 2007323    Ordinal date (basic)
  #     %Y-%j        # 2007-323   Ordinal date (extended)
  #     %GW%V%u      # 2007W471   Week date (basic)
  #     %G-W%V-%u    # 2007-W47-1 Week date (extended)
  #     %GW%V        # 2007W47    Week date, reduced accuracy, specific week (basic)
  #     %G-W%V       # 2007-W47   Week date, reduced accuracy, specific week (extended)
  #
  -> strftime/1
