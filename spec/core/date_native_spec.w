# Native packed-Date accessors and Gregorian/ISO calendar calculations.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

leap_day = 2024-02-29T23:59:58-05:00
check("year", leap_day.year, 2024)
check("month", leap_day.month, 2)
check("day", leap_day.day, 29)
check("hour", leap_day.hour, 23)
check("minute", leap_day.minute, 59)
check("second", leap_day.second, 58)
check("tz", leap_day.tz, -300)
check("quarter", leap_day.quarter, 1)
check("leap", leap_day.leap?, true)
check("leap_year", leap_day.leap_year?, true)
check("days_in_month", leap_day.days_in_month, 29)
check("days_in_year", leap_day.days_in_year, 366)
check("day_of_month", leap_day.day_of_month, 29)
check("day_of_year", leap_day.day_of_year, 60)
check("yday", leap_day.yday, 60)
check("wday", leap_day.wday, 4)
check("day_of_week", leap_day.day_of_week, 4)
check("cwday", leap_day.cwday, 4)
check("cweek", leap_day.cweek, 9)
check("cwyear", leap_day.cwyear, 2024)
check("jd", leap_day.jd, 2_460_370)

year_end = 2015-12-31
check("iso year end week", year_end.cweek, 53)
check("iso year end weekday", year_end.cwday, 4)
check("iso year end year", year_end.cwyear, 2015)

year_start = 2016-01-01
check("iso year start week", year_start.cweek, 53)
check("iso year start weekday", year_start.cwday, 5)
check("iso year start year", year_start.cwyear, 2015)

next_iso_year = 2018-12-31
check("next iso year week", next_iso_year.cweek, 1)
check("next iso year", next_iso_year.cwyear, 2019)

negative_year = Date.parse("-1024-01-01")
check("signed year minimum", negative_year.year, -1024)
check("year 2050", Date.parse("2050-06-15").year, 2050)
check("year 2050 literal", 2050-06-15, Date.new(2050, 6, 15))
check("year 3071", Date.new(3071, 12, 31).year, 3071)

invalid_parse_day = false
begin
  Date.parse("2024-02-30")
rescue error
  invalid_parse_day = true
check("invalid parse day rejected", invalid_parse_day, true)

invalid_parse_month = false
begin
  Date.parse("2024-13-01")
rescue error
  invalid_parse_month = true
check("invalid parse month rejected", invalid_parse_month, true)

invalid_parse_hour = false
begin
  Date.parse("2024-01-01T25:00:00")
rescue error
  invalid_parse_hour = true
check("invalid parse hour rejected", invalid_parse_hour, true)

sweden = Date.parse("1712-02-30")
check("sweden 1712-02-30 year", sweden.year, 1712)
check("sweden 1712-02-30 month", sweden.month, 2)
check("sweden 1712-02-30 day", sweden.day, 30)
catchup = Date.new(1712, 2, 30)
check("sweden Date.new catch-up", catchup.day, 30)
sweden_lit = 1712-02-30
check("sweden date literal day", sweden_lit.day, 30)
julian_leap = Date.parse("1700-02-29")
check("julian century leap 1700", julian_leap.day, 29)
check("julian century leap 1800", Date.parse("1800-02-29").day, 29)
check("julian century leap 1900", Date.parse("1900-02-29").day, 29)
check("julian century leap literal", (1900-02-29).day, 29)

check("ordinal 1867-250", 1867-250, Date.new(1867, 9, 7))
check("ordinal Date.ordinal", Date.ordinal(1867, 250), Date.new(1867, 9, 7))
check("ordinal 1867-250 month", (1867-250).month, 9)
check("ordinal 1867-250 day", (1867-250).day, 7)
check("sweden ordinal 61 is Feb 30", 1712-061, Date.new(1712, 2, 30))
check("sweden Feb 29 + 1", 1712-02-29 + 1, 1712-02-30)
check("sweden Feb 30 + 1", 1712-02-30 + 1, 1712-03-01)
check("samoa first July 4", 1892-186, Date.new(1892, 7, 4))
check("samoa repeated July 4", 1892-187, Date.new(1892, 7, 4))
check("samoa same date twice", 1892-186, 1892-187)
check("samoa day after the pair", 1892-188, Date.new(1892, 7, 5))
check("alaska last Friday Julian", 1867-279, Date.new(1867, 10, 6))
check("alaska next local midnight", 1867-280, Date.new(1867, 10, 18))

leap_sec = Date.parse("2016-12-31T23:59:60Z")
check("leap second literal", 2016-12-31T23:59:60Z, leap_sec)
check("leap second year", leap_sec.year, 2016)
check("leap second month", leap_sec.month, 12)
check("leap second day", leap_sec.day, 31)
check("leap second hour", leap_sec.hour, 23)
check("leap second minute", leap_sec.minute, 59)
check("leap second second", leap_sec.second, 60)
check("leap second tz", leap_sec.tz, 0)
check("leap second Date.new", Date.new(2016, 12, 31, 23, 59, 60, 0).second, 60)
check("leap second 2015 June", Date.parse("2015-06-30T23:59:60Z").second, 60)
check("leap second omitted zone", Date.parse("2016-12-31T23:59:60").second, 60)
check("nepal +05:45", Date.parse("2024-01-01T12:00:00+05:45").tz, 345)

bogus_leap = false
begin
  Date.parse("2024-01-01T23:59:60Z")
rescue error
  bogus_leap = true
check("random second 60 rejected", bogus_leap, true)

midday_sixty = false
begin
  Date.parse("2016-12-31T12:00:60Z")
rescue error
  midday_sixty = true
check("midday second 60 rejected", midday_sixty, true)

offset_leap = false
begin
  Date.parse("2016-12-31T23:59:60+01:00")
rescue error
  offset_leap = true
check("non-UTC leap second rejected", offset_leap, true)

check("amsterdam +00:20 packed", Date.parse("1937-07-01T12:00:00+00:20").tz, 20)

not_june_2016 = false
begin
  Date.parse("2016-06-30T23:59:60Z")
rescue error
  not_june_2016 = true
check("2016-06-30 was not a leap second", not_june_2016, true)

<< "date_native_spec: all checks passed"
