# Date methods must preserve source/native dispatch when the receiver's static
# type is erased at a function boundary.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> date_year(value)
  value.year

-> date_month(value)
  value.month

-> date_day_of_quarter(value)
  value.day_of_quarter

-> date_week(value)
  value.cweek

-> date_week_year(value)
  value.cwyear

-> date_name(value)
  value.day_name

-> date_month_name(value)
  value.month_name

-> date_format(value, format)
  value.strftime(format)

-> date_string(value)
  value.to_s()

-> date_ctime(value)
  value.ctime

-> date_asctime(value)
  value.asctime

parsed = Date.parse("2026-07-04")
check("parse class", parsed.class.to_s(), "Date")
check("erased year", date_year(parsed), 2026)
check("erased month", date_month(parsed), 7)
check("erased day of quarter", date_day_of_quarter(parsed), 4)
check("erased week", date_week(parsed), 27)
check("erased week year", date_week_year(parsed), 2026)
check("erased day name", date_name(parsed), "Saturday")
check("erased month name", date_month_name(parsed), "July")
check("erased native format", date_format(parsed, "%Y/%m/%d"), "2026/07/04")
check("erased native string", date_string(parsed), "2026-07-04T00:00:00Z")
check("erased ctime", date_ctime(parsed), "Sat Jul  4 00:00:00 2026")
check("erased asctime", date_asctime(parsed), "Sat Jul  4 00:00:00 2026")

quarter_end = 2024-06-30
check("leap quarter day", date_day_of_quarter(quarter_end), 91)

<< "date_dynamic_receiver_spec: all checks passed"
