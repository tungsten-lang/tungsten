# Semiprime

-> semiprime?(n)
  if n < 4
    return false
  count = 0
  d = 2
  while d * d <= n && count < 2
    while n % d == 0
      n /= d
      count += 1
    d += 1
  if n > 1
    count += 1
  count == 2

found = []
(1..100).each -> (n)
  if semiprime?(n)
    found.push(n)

<< found

## expect stdout
## [4, 6, 9, 10, 14, 15, 21, 22, 25, 26, 33, 34, 35, 38, 39, 46, 49, 51, 55, 57, 58, 62, 65, 69, 74, 77, 82, 85, 86, 87, 91, 93, 94, 95]
