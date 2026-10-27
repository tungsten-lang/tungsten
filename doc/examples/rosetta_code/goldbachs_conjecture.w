# Goldbach's conjecture

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

-> goldbach_pair(n)
  p = 2
  while p <= n / 2
    if prime?(p) && prime?(n - p)
      return [p, n - p]
    p += 1
  [0, 0]

evens = [4, 6, 8, 10, 28, 100, 1000]
evens.each -> (n)
  pair = goldbach_pair(n)
  << "[n] = [pair[0]] + [pair[1]]"

## expect stdout
## 4 = 2 + 2
## 6 = 3 + 3
## 8 = 3 + 5
## 10 = 3 + 7
## 28 = 5 + 23
## 100 = 3 + 97
## 1000 = 3 + 997
