# Day of the week (Yuletide Sundays via Zeller's congruence)

-> day_of_week(year, month, day)
  if month < 3
    month += 12
    year -= 1
  k = year % 100
  j = year / 100
  h = (day + (13 * (month + 1)) / 5 + k + k / 4 + j / 4 + 5 * j) % 7
  # h == 1 is Sunday
  h

sundays = []
(2008..2121).each -> (y)
  if day_of_week(y, 12, 25) == 1
    sundays.push(y)

<< sundays.join(" ")

## expect stdout
## 2011 2016 2022 2033 2039 2044 2050 2061 2067 2072 2078 2089 2095 2101 2107 2112 2118
