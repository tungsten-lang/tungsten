+ Date
  is Enumerable

  DAYS        = %w[Sun Mon Tue Wed Thu Fri Sat]
  DAY_NAMES   = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday]

  MONTHS      = %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec]
  MONTH_NAMES = %w[January February March April May June July August September October November December]

  FORMATS = {ctime: "%a %b %e 00:00:00 %Y", http: "%a, %d, %b, %Y 00:00:00 GMT", iso8601: "%Y-%m-%d", rfc3339: "%Y-%m-%dT00:00:00+00:00", rfc2822: "%a, %-d %b %Y 00:00:00 +0000", rfc822: "%a, %-d %b %Y 00:00:00 +0000"}

  -> .parse(string)

  -> new
  -> julian/1
  -> ordinal(year, num)
  -> commercial(year, week, day)

  -> today
  -> tomorrow

  -> day
  -> week
  -> month
  -> quarter
  -> year
  -> decade
  -> century
  -> millenium

  alias_mistake :asctime, :ctime
  -> ctime
    strftime FORMATS[:ctime]

  -> cwday
  -> cweek
  -> cwyear

  -> wday

  -> day_abbr
    DAYS[day_of_week]

  -> day_name
    DAY_NAMES[day_of_week]

  -> month_abbr
    MONTHS[month]

  -> month_name
    MONTH_NAMES[month]

  -> quarter_abbr
    "Q[quarter]"

  -> year_with_quarter
    "[year]Q[quarter]"

  -> decade_abbr
    "[decade]s"

  alias_mistake :wday, :day_of_week
  -> day_of_week
  -> day_of_month
  -> day_of_quarter
  -> day_of_year

  -> days_in_month
  -> days_in_year

  -> first_of_week
  -> first_of_month
  -> first_of_quarter
  -> first_of_year
  -> first_of_decade
  -> first_of_century
  -> first_of_millenium

  -> last_of_week
  -> last_of_month
  -> last_of_quarter
  -> last_of_year
  -> last_of_decade
  -> last_of_century
  -> last_of_millenium

  -> leap_year?

  -> wday

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
