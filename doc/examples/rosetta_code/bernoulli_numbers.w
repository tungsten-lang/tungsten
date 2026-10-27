# Bernoulli numbers

-> gcd(a, b)
  if a < 0
    a = -a
  if b < 0
    b = -b
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> rat_sub(a, b)
  num = a[0] * b[1] - b[0] * a[1]
  den = a[1] * b[1]
  g = gcd(num, den)
  [num / g, den / g]

-> rat_mul_int(a, k)
  num = a[0] * k
  den = a[1]
  g = gcd(num, den)
  [num / g, den / g]

-> bernoulli(max_n)
  a = []
  m = 0
  while m <= max_n
    a.push([1, m + 1])
    j = m
    while j >= 1
      diff = rat_sub(a[j - 1], a[j])
      a[j - 1] = rat_mul_int(diff, j)
      j -= 1
    if a[0][0] != 0
      << "B([m]) = [a[0][0]]/[a[0][1]]"
    m += 1

bernoulli(14)

## expect stdout
## B(0) = 1/1
## B(1) = 1/2
## B(2) = 1/6
## B(4) = -1/30
## B(6) = 1/42
## B(8) = -1/30
## B(10) = 5/66
## B(12) = -691/2730
## B(14) = 7/6
