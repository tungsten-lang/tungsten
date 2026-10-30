# Sum multiples of 3 and 5

-> sum_multiples(limit)
  total = 0
  n = 1
  while n < limit
    if n % 3 == 0 || n % 5 == 0
      total += n
    n += 1
  total

<< sum_multiples(1000)

## expect stdout
## 233168
