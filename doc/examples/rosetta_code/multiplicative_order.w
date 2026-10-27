# Multiplicative order

-> gcd(a, b)
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> mult_order(a, m)
  if gcd(a, m) != 1
    return -1
  k = 1
  p = a % m
  while p != 1
    p = (p * a) % m
    k += 1
  k

<< mult_order(3, 10)
<< mult_order(37, 1000)
<< mult_order(2, 1001)

## expect stdout
## 4
## 100
## 60
