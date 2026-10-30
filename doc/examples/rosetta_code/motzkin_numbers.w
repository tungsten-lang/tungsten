# Motzkin numbers

-> motzkin(count)
  m = [1, 1]
  n = 2
  while n < count
    next_m = ((2 * n + 1) * m[n - 1] + (3 * n - 3) * m[n - 2]) / (n + 2)
    m.push(next_m)
    n += 1
  m

<< motzkin(15)

## expect stdout
## [1, 1, 2, 4, 9, 21, 51, 127, 323, 835, 2188, 5798, 15511, 41835, 113634]
