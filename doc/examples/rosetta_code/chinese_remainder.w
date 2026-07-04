# Chinese remainder theorem

-> extended_gcd(a, b)
  if a == 0
    return [b, 0, 1]
  result = extended_gcd(b % a, a)
  g = result[0]
  x = result[1]
  y = result[2]
  [g, y - (b / a) * x, x]

-> chinese_remainder(remainders, moduli)
  prod = 1
  i = 0
  while i < moduli.size
    prod *= moduli[i]
    i += 1
  sum = 0
  i = 0
  while i < remainders.size
    p = prod / moduli[i]
    result = extended_gcd(p, moduli[i])
    sum += remainders[i] * result[1] * p
    i += 1
  sum % prod

<< chinese_remainder([2, 3, 2], [3, 5, 7])

## expect stdout
## 23
