# Modular exponentiation

-> mod_pow(base, exp, mod)
  result = 1
  b = base % mod
  e = exp
  while e > 0
    if e % 2 == 1
      result = (result * b) % mod
    b = (b * b) % mod
    e /= 2
  result

<< mod_pow(2, 10, 1000)
<< mod_pow(7, 256, 13)
<< mod_pow(1234567, 891011, 1000000007)

## expect stdout
## 24
## 9
## 884528673
