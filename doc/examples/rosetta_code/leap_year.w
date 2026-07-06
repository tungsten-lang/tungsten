# Leap year

-> leap?(year)
  if year % 400 == 0
    true
  elsif year % 100 == 0
    false
  elsif year % 4 == 0
    true
  else
    false

years = [1900, 2000, 2024, 2025, 2100]
years.each -> (y)
  if leap?(y)
    << "[y] is a leap year"
  else
    << "[y] is not a leap year"

## expect stdout
## 1900 is not a leap year
## 2000 is a leap year
## 2024 is a leap year
## 2025 is not a leap year
## 2100 is not a leap year
