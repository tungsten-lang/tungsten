+ Month
  DAYS_IN_MONTH = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

  -> days
    parts = self.to_s().split("-")
    year = parts[0].to_i()
    month = parts[1].to_i()
    last = DAYS_IN_MONTH[month]
    if month == 2
      is_leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
      if is_leap
        last = 29
    first_str = year.to_s() + "-" + month.to_s().rjust(2, "0") + "-01"
    last_str = year.to_s() + "-" + month.to_s().rjust(2, "0") + "-" + last.to_s().rjust(2, "0")
    first_str..last_str
