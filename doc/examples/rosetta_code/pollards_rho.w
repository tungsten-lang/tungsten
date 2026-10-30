# Pollard's rho algorithm

-> gcd(a, b)
  if a < 0
    a = -a
  while b != 0
    t = a % b
    a = b
    b = t
  a

-> pollard_rho(n)
  if n % 2 == 0
    return 2
  c = 1
  while c < n
    x = 2
    y = 2
    d = 1
    while d == 1
      x = (x * x + c) % n
      y = (y * y + c) % n
      y = (y * y + c) % n
      d = gcd(x - y, n)
    if d != n
      return d
    c += 1
  n

nums = [8051, 10403, 25217]
nums.each -> (n)
  f = pollard_rho(n)
  << "[n] = [f] * [n / f]"

## expect stdout
## 8051 = 97 * 83
## 10403 = 101 * 103
## 25217 = 167 * 151
