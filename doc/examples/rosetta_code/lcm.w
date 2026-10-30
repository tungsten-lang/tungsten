# Least common multiple

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

-> lcm(a, b)
  if a == 0 || b == 0
    return 0
  p = a / gcd(a, b) * b
  if p < 0
    -p
  else
    p

<< lcm(12, 18)
<< lcm(-6, 14)
<< lcm(21, 6)
<< lcm(0, 5)

## expect stdout
## 36
## 42
## 42
## 0
