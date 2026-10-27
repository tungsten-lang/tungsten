# Cramer's rule

-> minor(m, row, col)
  sub = []
  r = 0
  while r < m.size
    if r != row
      line = []
      c = 0
      while c < m.size
        if c != col
          line.push(m[r][c])
        c += 1
      sub.push(line)
    r += 1
  sub

-> det(m)
  n = m.size
  if n == 1
    return m[0][0]
  if n == 2
    return m[0][0] * m[1][1] - m[0][1] * m[1][0]
  total = 0
  sign = 1
  c = 0
  while c < n
    total += sign * m[0][c] * det(minor(m, 0, c))
    sign = -sign
    c += 1
  total

-> replace_col(m, b, col)
  out = []
  r = 0
  while r < m.size
    row = []
    c = 0
    while c < m.size
      if c == col
        row.push(b[r])
      else
        row.push(m[r][c])
      c += 1
    out.push(row)
    r += 1
  out

a = [
  [2, -1, 5, 1],
  [3, 2, 2, -6],
  [1, 3, 3, -1],
  [5, -2, -3, 3]
]
b = [-3, -32, -47, 49]

d = det(a)
sol = []
(0...4).each -> (col)
  sol.push(det(replace_col(a, b, col)) / d)

<< sol

## expect stdout
## [2, -12, -4, 1]
