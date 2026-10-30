# Smith numbers

-> digit_sum(n)
  s = 0
  while n > 0
    s += n % 10
    n /= 10
  s

-> smith?(n)
  if n < 4
    return false
  temp = n
  factor_digit_sum = 0
  factor_count = 0
  d = 2
  while d * d <= temp
    while temp % d == 0
      factor_digit_sum += digit_sum(d)
      temp /= d
      factor_count += 1
    d += 1
  if temp > 1
    if factor_count == 0
      return false
    factor_digit_sum += digit_sum(temp)
  factor_digit_sum == digit_sum(n)

found = []
(4..500).each -> (n)
  if smith?(n)
    found.push(n)

<< found

## expect stdout
## [4, 22, 27, 58, 85, 94, 121, 166, 202, 265, 274, 319, 346, 355, 378, 382, 391, 438, 454, 483]
