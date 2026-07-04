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
years.each { |y|
  if leap?(y)
    puts "[y] is a leap year"
  else
    puts "[y] is not a leap year"
}

## expect skip currently unsupported in this runtime
