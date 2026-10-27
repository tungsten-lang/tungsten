# Happy numbers

-> sum_of_squares(n)
  total = 0
  while n > 0
    d = n % 10
    total += d * d
    n = n / 10
  total

-> happy?(n)
  seen = []
  while n != 1
    if seen.include?(n)
      return false
    seen.push(n)
    n = sum_of_squares(n)
  true

-> first_happy(limit)
  count = 0
  n = 1
  while count < limit
    if happy?(n)
      << n
      count += 1
    n += 1

first_happy(8)

## expect stdout
## 1
## 7
## 10
## 13
## 19
## 23
## 28
## 31
