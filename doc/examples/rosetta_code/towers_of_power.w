# Power function / Exponentiation

-> power(base, exp)
  if exp == 0
    return 1
  result = 1
  while exp > 0
    if exp % 2 == 1
      result *= base
    base *= base
    exp = exp / 2
  result

<< power(2, 10)
<< power(3, 5)
<< power(10, 6)

## expect stdout
## 1024
## 243
## 1000000
