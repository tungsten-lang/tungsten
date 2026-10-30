# Lucas-Lehmer test

-> prime?(n)
  if n < 2
    return false
  if n == 2
    return true
  if n % 2 == 0
    return false
  d = 3
  while d * d <= n
    if n % d == 0
      return false
    d += 2
  true

-> lucas_lehmer?(p)
  if p == 2
    return true
  if !prime?(p)
    return false
  m = (1 << p) - 1
  s = 4
  i = 0
  while i < p - 2
    s = (s * s - 2) % m
    i += 1
  s == 0

exponents = []
(2..31).each -> (p)
  if lucas_lehmer?(p)
    exponents.push("M[p]")

<< exponents.join(" ")

## expect stdout
## M2 M3 M5 M7 M13 M17 M19 M31
