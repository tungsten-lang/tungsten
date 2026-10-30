# Kaprekar numbers

-> kaprekar?(n)
  if n == 1
    return true
  sq = n * n
  pow10 = 10
  while pow10 <= sq
    left = sq / pow10
    right = sq % pow10
    if right > 0 && left + right == n
      return true
    pow10 *= 10
  false

found = []
(1..1000).each -> (n)
  if kaprekar?(n)
    found.push(n)

<< found

## expect stdout
## [1, 9, 45, 55, 99, 297, 703, 999]
