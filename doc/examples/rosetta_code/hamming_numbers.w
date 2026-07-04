# Hamming numbers (regular numbers: 2^i * 3^j * 5^k)

-> hamming(n)
  h = [1]
  i2 = 0
  i3 = 0
  i5 = 0
  while h.size < n
    x2 = h[i2] * 2
    x3 = h[i3] * 3
    x5 = h[i5] * 5
    m = x2
    if x3 < m
      m = x3
    if x5 < m
      m = x5
    h.push(m)
    if m == x2
      i2 += 1
    if m == x3
      i3 += 1
    if m == x5
      i5 += 1
  h

<< hamming(20)

## expect stdout
## [1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 15, 16, 18, 20, 24, 25, 27, 30, 32, 36]
