# Date construction and calendar-period helpers across static and erased class
# dispatch. The packed representation is limited to years -2048..2047.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> erased_new(klass, year, month, day)
  klass.new(year, month, day)

-> erased_julian(klass, number)
  klass.julian(number)

leap = Date.new(2024, 2, 29, 23, 59, 58, -300)
check("new type", type(leap), "Date")
check("new year", leap.year, 2024)
check("new month", leap.month, 2)
check("new day", leap.day, 29)
check("new hour", leap.hour, 23)
check("new minute", leap.minute, 59)
check("new second", leap.second, 58)
check("new timezone", leap.tz, -300)

defaults = Date.new(2026)
check("new default month", defaults.month, 1)
check("new default day", defaults.day, 1)
check("new default time", defaults.hour + defaults.minute + defaults.second, 0)
check("new default timezone", defaults.tz, 0)

dynamic = erased_new(Date, 2026, 7, 4)
check("erased new", dynamic.to_s(), "2026-07-04T00:00:00Z")

jd = Date.julian(2_460_370)
check("julian year", jd.year, 2024)
check("julian month", jd.month, 2)
check("julian day", jd.day, 29)
check("erased julian", erased_julian(Date, 2_460_370), jd)

ordinal = Date.ordinal(2024, 60)
check("ordinal leap day", ordinal, jd)
commercial = Date.commercial(2015, 53, 4)
check("commercial year", commercial.year, 2015)
check("commercial month", commercial.month, 12)
check("commercial day", commercial.day, 31)
check("week alias", commercial.week, 53)

period = Date.new(2024, 2, 29, 12, 34, 56, 330)
check("first week", period.first_of_week.to_s(), "2024-02-26T12:34:56+05:30")
check("last week", period.last_of_week.to_s(), "2024-03-03T12:34:56+05:30")
check("first month", period.first_of_month.to_s(), "2024-02-01T12:34:56+05:30")
check("last month", period.last_of_month.to_s(), "2024-02-29T12:34:56+05:30")
check("first quarter", period.first_of_quarter.to_s(), "2024-01-01T12:34:56+05:30")
check("last quarter", period.last_of_quarter.to_s(), "2024-03-31T12:34:56+05:30")
check("first year", period.first_of_year.to_s(), "2024-01-01T12:34:56+05:30")
check("last year", period.last_of_year.to_s(), "2024-12-31T12:34:56+05:30")

wide = Date.new(1904, 6, 15)
check("decade", wide.decade, 1900)
check("decade abbreviation", wide.decade_abbr, "1900s")
check("century", wide.century, 1900)
check("millenium", wide.millenium, 1000)
check("millennium alias", wide.millennium, 1000)
check("first decade", wide.first_of_decade.to_s(), "1900-01-01T00:00:00Z")
check("last decade", wide.last_of_decade.to_s(), "1909-12-31T00:00:00Z")
check("first century", wide.first_of_century.to_s(), "1900-01-01T00:00:00Z")
check("last century", wide.last_of_century.to_s(), "1999-12-31T00:00:00Z")
check("first millenium", wide.first_of_millenium.to_s(), "1000-01-01T00:00:00Z")
check("last millennium alias", wide.last_of_millennium.to_s(), "1999-12-31T00:00:00Z")

bce = Date.new(-1, 1, 1)
check("negative decade floors", bce.decade, -10)
check("negative century floors", bce.century, -100)
check("negative millennium floors", bce.millennium, -1000)

invalid_day = false
begin
  Date.new(2023, 2, 29)
rescue error
  invalid_day = true
check("invalid day rejected", invalid_day, true)

invalid_ordinal = false
begin
  Date.ordinal(2023, 366)
rescue error
  invalid_ordinal = true
check("invalid ordinal rejected", invalid_ordinal, true)

invalid_week = false
begin
  Date.commercial(2021, 53, 1)
rescue error
  invalid_week = true
check("invalid ISO week rejected", invalid_week, true)

upper_overflow = false
begin
  Date.new(2047, 12, 31) + 1
rescue error
  upper_overflow = true
check("upper year overflow rejected", upper_overflow, true)

lower_overflow = false
begin
  Date.new(-2048, 1, 1) - 1
rescue error
  lower_overflow = true
check("lower year overflow rejected", lower_overflow, true)

huge_shift = false
begin
  Date.new(2000, 1, 1) + 10_000_000
rescue error
  huge_shift = true
check("huge day shift rejected", huge_shift, true)

today = Date.today
check("today type", type(today), "Date")
check("today midnight", today.hour + today.minute + today.second, 0)
check("tomorrow follows today", Date.tomorrow - today, 1)

<< "date_calendar_surface_spec: all checks passed"
