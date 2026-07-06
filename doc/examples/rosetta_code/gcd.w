# Greatest common divisor

-> gcd(a, b)
  if b == 0
    a
  else
    gcd(b, a % b)

<< gcd(12, 8)
<< gcd(100, 75)
<< gcd(1071, 462)

## expect stdout
## 4
## 25
## 21
