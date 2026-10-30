# Euler's totient function

-> totient(n)
  result = n
  p = 2
  temp = n
  while p * p <= temp
    if temp % p == 0
      while temp % p == 0
        temp /= p
      result -= result / p
    p += 1
  if temp > 1
    result -= result / temp
  result

out = []
(1..20).each -> (n)
  out.push(totient(n))

<< out

## expect stdout
## [1, 1, 2, 2, 4, 2, 6, 4, 6, 4, 10, 4, 12, 6, 8, 8, 16, 6, 18, 8]
