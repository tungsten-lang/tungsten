# Function-level A/B benchmark for Date methods moved from runtime.c into
# core/date.w. C references are linked only into this benchmark. Compilation,
# process startup, and corpus construction are excluded from timed intervals.

use ../../core/date

CORPUS_SIZE = 4096
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 10_000_000
WARMUP_ITERS = 50_000

+ Date
  -> __c_year
    ccall("w_ref_date_year", self)

  -> __c_month
    ccall("w_ref_date_month", self)

  -> __c_day
    ccall("w_ref_date_day", self)

  -> __c_hour
    ccall("w_ref_date_hour", self)

  -> __c_minute
    ccall("w_ref_date_minute", self)

  -> __c_second
    ccall("w_ref_date_second", self)

  -> __c_wday
    ccall("w_ref_date_wday", self)

  -> __c_day_of_week
    ccall("w_ref_date_wday", self)

  -> __c_day_of_month
    ccall("w_ref_date_day", self)

  -> __c_day_of_year
    ccall("w_ref_date_yday", self)

  -> __c_yday
    ccall("w_ref_date_yday", self)

  -> __c_cweek
    ccall("w_ref_date_cweek", self)

  -> __c_cwday
    ccall("w_ref_date_cwday", self)

  -> __c_days_in_month
    ccall("w_ref_date_days_in_month", self)

  -> __c_days_in_year
    ccall("w_ref_date_days_in_year", self)

  -> __c_leap?
    ccall("w_ref_date_leap_p", self)

  -> __c_jd
    ccall("w_ref_date_jd", self)

  -> __c_quarter
    ccall("w_ref_date_quarter", self)

  -> __c_tz
    ccall("w_ref_date_tz", self)

-> make_date(year, month, day, hour = 0, minute = 0, second = 0, tz = 0)
  ccall("w_date", year, month, day, hour, minute, second, tz)

-> days_for(year, month)
  if month == 2
    leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    return leap ? 29 : 28
  if month == 4 || month == 6 || month == 9 || month == 11
    return 30
  31

-> fail_check(name, case_index, got, expected)
  << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(name, case_index, got, expected)
  if got != expected
    fail_check(name, case_index, got, expected)

-> check_calendar(date, case_index)
  check_value("year", case_index, date.year, date.__c_year)
  check_value("month", case_index, date.month, date.__c_month)
  check_value("day", case_index, date.day, date.__c_day)
  check_value("hour", case_index, date.hour, date.__c_hour)
  check_value("minute", case_index, date.minute, date.__c_minute)
  check_value("second", case_index, date.second, date.__c_second)
  check_value("wday", case_index, date.wday, date.__c_wday)
  check_value("day_of_week", case_index, date.day_of_week, date.__c_day_of_week)
  check_value("day_of_month", case_index, date.day_of_month, date.__c_day_of_month)
  check_value("day_of_year", case_index, date.day_of_year, date.__c_day_of_year)
  check_value("yday", case_index, date.yday, date.__c_yday)
  check_value("cweek", case_index, date.cweek, date.__c_cweek)
  check_value("cwday", case_index, date.cwday, date.__c_cwday)
  check_value("days_in_month", case_index, date.days_in_month, date.__c_days_in_month)
  check_value("days_in_year", case_index, date.days_in_year, date.__c_days_in_year)
  check_value("leap?", case_index, date.leap?, date.__c_leap?)
  check_value("jd", case_index, date.jd, date.__c_jd)
  check_value("quarter", case_index, date.quarter, date.__c_quarter)
  check_value("tz", case_index, date.tz, date.__c_tz)

-> run_correctness
  # Every valid day in a complete Gregorian 400-year cycle. This exhausts
  # weekday, leap-century, ordinal-day, JDN, and ISO-week boundary behavior.
  checked = 0
  case_index = 0
  year = 1600
  while year <= 1999
    month = 1
    while month <= 12
      max_day = days_for(year, month)
      day = 1
      while day <= max_day
        date = make_date(year, month, day,
                         day % 24, (day * 7) % 60, (day * 11) % 60,
                         ((day + month) % 65 - 32) * 15)
        check_calendar(date, case_index)
        checked += 19
        case_index += 1
        day += 1
      month += 1
    year += 1

  # Exhaust every signed year encoding and every hour/minute/second/timezone
  # field encoding. Invalid clock values are intentional here: the packed
  # accessors must preserve all bit patterns exactly, just as the old C did.
  raw_year = -2048
  while raw_year <= 2047
    i = raw_year + 2048
    date = make_date(raw_year, i % 12 + 1, i % 28 + 1,
                     i % 32, i % 64, (i * 17) % 64,
                     (i % 128 - 64) * 15)
    check_value("year.bits", i, date.year, date.__c_year)
    check_value("month.bits", i, date.month, date.__c_month)
    check_value("day.bits", i, date.day, date.__c_day)
    check_value("hour.bits", i, date.hour, date.__c_hour)
    check_value("minute.bits", i, date.minute, date.__c_minute)
    check_value("second.bits", i, date.second, date.__c_second)
    check_value("tz.bits", i, date.tz, date.__c_tz)
    checked += 7
    raw_year += 1

  << "correctness: ok ([checked] exact C/W comparisons; full 400-year cycle)"

-> build_corpus
  dates = []
  state = 0x6D2B79F5
  i = 0
  while i < CORPUS_SIZE
    state = (state * 1_664_525 + 1_013_904_223) & 0x7FFFFFFF
    year = 1600 + i % 400
    month = state % 12 + 1
    day = (state / 12) % days_for(year, month) + 1
    hour = (state / 97) % 24
    minute = (state / 193) % 60
    second = (state / 389) % 60
    tz = ((i % 107) - 53) * 15
    dates.push(make_date(year, month, day, hour, minute, second, tz))
    i += 1
  dates

-> finish_timing(start_s, checksum)
  [clock() - start_s, checksum]

-> time_year_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_year
    i += 1
  finish_timing(start_s, checksum)

-> time_year_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].year
    i += 1
  finish_timing(start_s, checksum)

-> time_month_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_month
    i += 1
  finish_timing(start_s, checksum)

-> time_month_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].month
    i += 1
  finish_timing(start_s, checksum)

-> time_day_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_day
    i += 1
  finish_timing(start_s, checksum)

-> time_day_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].day
    i += 1
  finish_timing(start_s, checksum)

-> time_hour_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_hour
    i += 1
  finish_timing(start_s, checksum)

-> time_hour_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].hour
    i += 1
  finish_timing(start_s, checksum)

-> time_minute_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_minute
    i += 1
  finish_timing(start_s, checksum)

-> time_minute_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].minute
    i += 1
  finish_timing(start_s, checksum)

-> time_second_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_second
    i += 1
  finish_timing(start_s, checksum)

-> time_second_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].second
    i += 1
  finish_timing(start_s, checksum)

-> time_wday_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_wday
    i += 1
  finish_timing(start_s, checksum)

-> time_wday_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].wday
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_week_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_day_of_week
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_week_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].day_of_week
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_month_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_day_of_month
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_month_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].day_of_month
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_year_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_day_of_year
    i += 1
  finish_timing(start_s, checksum)

-> time_day_of_year_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].day_of_year
    i += 1
  finish_timing(start_s, checksum)

-> time_yday_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_yday
    i += 1
  finish_timing(start_s, checksum)

-> time_yday_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].yday
    i += 1
  finish_timing(start_s, checksum)

-> time_cweek_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_cweek
    i += 1
  finish_timing(start_s, checksum)

-> time_cweek_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].cweek
    i += 1
  finish_timing(start_s, checksum)

-> time_cwday_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_cwday
    i += 1
  finish_timing(start_s, checksum)

-> time_cwday_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].cwday
    i += 1
  finish_timing(start_s, checksum)

-> time_days_in_month_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_days_in_month
    i += 1
  finish_timing(start_s, checksum)

-> time_days_in_month_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].days_in_month
    i += 1
  finish_timing(start_s, checksum)

-> time_days_in_year_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_days_in_year
    i += 1
  finish_timing(start_s, checksum)

-> time_days_in_year_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].days_in_year
    i += 1
  finish_timing(start_s, checksum)

-> time_leap_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_leap? ? 1 : 0
    i += 1
  finish_timing(start_s, checksum)

-> time_leap_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].leap? ? 1 : 0
    i += 1
  finish_timing(start_s, checksum)

-> time_jd_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_jd
    i += 1
  finish_timing(start_s, checksum)

-> time_jd_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].jd
    i += 1
  finish_timing(start_s, checksum)

-> time_quarter_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_quarter
    i += 1
  finish_timing(start_s, checksum)

-> time_quarter_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].quarter
    i += 1
  finish_timing(start_s, checksum)

-> time_tz_c(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].__c_tz
    i += 1
  finish_timing(start_s, checksum)

-> time_tz_w(dates, iters)
  checksum = 0
  i = 0
  start_s = clock()
  while i < iters
    checksum += dates[i & CORPUS_MASK].tz
    i += 1
  finish_timing(start_s, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum [name]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_bench(dates, iters, parity)
  # Warm each exact call site before measurement.
  time_year_c(dates, WARMUP_ITERS)
  time_year_w(dates, WARMUP_ITERS)
  time_month_c(dates, WARMUP_ITERS)
  time_month_w(dates, WARMUP_ITERS)
  time_day_c(dates, WARMUP_ITERS)
  time_day_w(dates, WARMUP_ITERS)
  time_hour_c(dates, WARMUP_ITERS)
  time_hour_w(dates, WARMUP_ITERS)
  time_minute_c(dates, WARMUP_ITERS)
  time_minute_w(dates, WARMUP_ITERS)
  time_second_c(dates, WARMUP_ITERS)
  time_second_w(dates, WARMUP_ITERS)
  time_wday_c(dates, WARMUP_ITERS)
  time_wday_w(dates, WARMUP_ITERS)
  time_day_of_week_c(dates, WARMUP_ITERS)
  time_day_of_week_w(dates, WARMUP_ITERS)
  time_day_of_month_c(dates, WARMUP_ITERS)
  time_day_of_month_w(dates, WARMUP_ITERS)
  time_day_of_year_c(dates, WARMUP_ITERS)
  time_day_of_year_w(dates, WARMUP_ITERS)
  time_yday_c(dates, WARMUP_ITERS)
  time_yday_w(dates, WARMUP_ITERS)
  time_cweek_c(dates, WARMUP_ITERS)
  time_cweek_w(dates, WARMUP_ITERS)
  time_cwday_c(dates, WARMUP_ITERS)
  time_cwday_w(dates, WARMUP_ITERS)
  time_days_in_month_c(dates, WARMUP_ITERS)
  time_days_in_month_w(dates, WARMUP_ITERS)
  time_days_in_year_c(dates, WARMUP_ITERS)
  time_days_in_year_w(dates, WARMUP_ITERS)
  time_leap_c(dates, WARMUP_ITERS)
  time_leap_w(dates, WARMUP_ITERS)
  time_jd_c(dates, WARMUP_ITERS)
  time_jd_w(dates, WARMUP_ITERS)
  time_quarter_c(dates, WARMUP_ITERS)
  time_quarter_w(dates, WARMUP_ITERS)
  time_tz_c(dates, WARMUP_ITERS)
  time_tz_w(dates, WARMUP_ITERS)

  # Reverse every adjacent C/W pair on odd process samples.
  if parity == 0
    c_result = time_year_c(dates, iters)
    w_result = time_year_w(dates, iters)
  else
    w_result = time_year_w(dates, iters)
    c_result = time_year_c(dates, iters)
  report_result("year", c_result, w_result, iters)

  if parity == 0
    c_result = time_month_c(dates, iters)
    w_result = time_month_w(dates, iters)
  else
    w_result = time_month_w(dates, iters)
    c_result = time_month_c(dates, iters)
  report_result("month", c_result, w_result, iters)

  if parity == 0
    c_result = time_day_c(dates, iters)
    w_result = time_day_w(dates, iters)
  else
    w_result = time_day_w(dates, iters)
    c_result = time_day_c(dates, iters)
  report_result("day", c_result, w_result, iters)

  if parity == 0
    c_result = time_hour_c(dates, iters)
    w_result = time_hour_w(dates, iters)
  else
    w_result = time_hour_w(dates, iters)
    c_result = time_hour_c(dates, iters)
  report_result("hour", c_result, w_result, iters)

  if parity == 0
    c_result = time_minute_c(dates, iters)
    w_result = time_minute_w(dates, iters)
  else
    w_result = time_minute_w(dates, iters)
    c_result = time_minute_c(dates, iters)
  report_result("minute", c_result, w_result, iters)

  if parity == 0
    c_result = time_second_c(dates, iters)
    w_result = time_second_w(dates, iters)
  else
    w_result = time_second_w(dates, iters)
    c_result = time_second_c(dates, iters)
  report_result("second", c_result, w_result, iters)

  if parity == 0
    c_result = time_wday_c(dates, iters)
    w_result = time_wday_w(dates, iters)
  else
    w_result = time_wday_w(dates, iters)
    c_result = time_wday_c(dates, iters)
  report_result("wday", c_result, w_result, iters)

  if parity == 0
    c_result = time_day_of_week_c(dates, iters)
    w_result = time_day_of_week_w(dates, iters)
  else
    w_result = time_day_of_week_w(dates, iters)
    c_result = time_day_of_week_c(dates, iters)
  report_result("day_of_week", c_result, w_result, iters)

  if parity == 0
    c_result = time_day_of_month_c(dates, iters)
    w_result = time_day_of_month_w(dates, iters)
  else
    w_result = time_day_of_month_w(dates, iters)
    c_result = time_day_of_month_c(dates, iters)
  report_result("day_of_month", c_result, w_result, iters)

  if parity == 0
    c_result = time_day_of_year_c(dates, iters)
    w_result = time_day_of_year_w(dates, iters)
  else
    w_result = time_day_of_year_w(dates, iters)
    c_result = time_day_of_year_c(dates, iters)
  report_result("day_of_year", c_result, w_result, iters)

  if parity == 0
    c_result = time_yday_c(dates, iters)
    w_result = time_yday_w(dates, iters)
  else
    w_result = time_yday_w(dates, iters)
    c_result = time_yday_c(dates, iters)
  report_result("yday", c_result, w_result, iters)

  if parity == 0
    c_result = time_cweek_c(dates, iters)
    w_result = time_cweek_w(dates, iters)
  else
    w_result = time_cweek_w(dates, iters)
    c_result = time_cweek_c(dates, iters)
  report_result("cweek", c_result, w_result, iters)

  if parity == 0
    c_result = time_cwday_c(dates, iters)
    w_result = time_cwday_w(dates, iters)
  else
    w_result = time_cwday_w(dates, iters)
    c_result = time_cwday_c(dates, iters)
  report_result("cwday", c_result, w_result, iters)

  if parity == 0
    c_result = time_days_in_month_c(dates, iters)
    w_result = time_days_in_month_w(dates, iters)
  else
    w_result = time_days_in_month_w(dates, iters)
    c_result = time_days_in_month_c(dates, iters)
  report_result("days_in_month", c_result, w_result, iters)

  if parity == 0
    c_result = time_days_in_year_c(dates, iters)
    w_result = time_days_in_year_w(dates, iters)
  else
    w_result = time_days_in_year_w(dates, iters)
    c_result = time_days_in_year_c(dates, iters)
  report_result("days_in_year", c_result, w_result, iters)

  if parity == 0
    c_result = time_leap_c(dates, iters)
    w_result = time_leap_w(dates, iters)
  else
    w_result = time_leap_w(dates, iters)
    c_result = time_leap_c(dates, iters)
  report_result("leap?", c_result, w_result, iters)

  if parity == 0
    c_result = time_jd_c(dates, iters)
    w_result = time_jd_w(dates, iters)
  else
    w_result = time_jd_w(dates, iters)
    c_result = time_jd_c(dates, iters)
  report_result("jd", c_result, w_result, iters)

  if parity == 0
    c_result = time_quarter_c(dates, iters)
    w_result = time_quarter_w(dates, iters)
  else
    w_result = time_quarter_w(dates, iters)
    c_result = time_quarter_c(dates, iters)
  report_result("quarter", c_result, w_result, iters)

  if parity == 0
    c_result = time_tz_c(dates, iters)
    w_result = time_tz_w(dates, iters)
  else
    w_result = time_tz_w(dates, iters)
    c_result = time_tz_c(dates, iters)
  report_result("tz", c_result, w_result, iters)

args = argv()
mode = args.size() > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
  exit(0)

iters = DEFAULT_ITERS
if args.size() > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = 0
if args.size() > 2
  if args[2] != "0" && args[2] != "1"
    << "sample parity must be 0 (C/W) or 1 (W/C)"
    exit(2)
  parity = args[2].to_i

run_bench(build_corpus(), iters, parity)
