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

negative_year = ccall("w_date", -2048, 1, 1, 0, 0, 0, 0)
check("signed year minimum", negative_year.year, -2048)

<< "date_native_spec: all checks passed"
