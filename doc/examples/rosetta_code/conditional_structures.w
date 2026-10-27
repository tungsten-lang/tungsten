# Conditional structures

-> classify(n)
  if n < 0
    "negative"
  elsif n == 0
    "zero"
  else
    "positive"

-> day_type(d)
  case d
  when 1, 2, 3, 4, 5
    "weekday"
  when 6, 7
    "weekend"
  else
    "unknown"

<< classify(-5)
<< classify(0)
<< classify(9)
<< day_type(3)
<< day_type(6)

## expect stdout
## negative
## zero
## positive
## weekday
## weekend
