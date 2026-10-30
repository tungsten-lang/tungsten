# Self-describing numbers

-> self_describing?(n)
  digits = []
  tmp = n
  if tmp == 0
    digits.push(0)
  while tmp > 0
    digits.push(tmp % 10)
    tmp /= 10
  digits = digits.reverse
  b = digits.size
  sum = 0
  i = 0
  while i < b
    sum += digits[i]
    i += 1
  if sum != b
    return false
  i = 0
  while i < b
    count = 0
    j = 0
    while j < b
      if digits[j] == i
        count += 1
      j += 1
    if count != digits[i]
      return false
    i += 1
  true

candidates = [1210, 2020, 21200, 3211000, 42101000]
candidates.each -> (n)
  if self_describing?(n)
    << n

## expect stdout
## 1210
## 2020
## 21200
## 3211000
## 42101000
