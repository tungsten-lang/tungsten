# Modular inverse

-> mod_inverse(a, m)
  t = 0
  new_t = 1
  r = m
  new_r = a % m
  while new_r != 0
    q = r / new_r
    tmp_t = t - q * new_t
    t = new_t
    new_t = tmp_t
    tmp_r = r - q * new_r
    r = new_r
    new_r = tmp_r
  if r > 1
    return -1
  if t < 0
    t += m
  t

<< mod_inverse(42, 2017)
<< mod_inverse(3, 11)
<< mod_inverse(10, 17)

## expect stdout
## 1969
## 4
## 12
