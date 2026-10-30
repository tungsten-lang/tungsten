# Matrix determinant and permanent

-> minor_matrix(m, skip_col)
  sub = []
  r = 1
  while r < m.size
    row = []
    c = 0
    while c < m.size
      if c != skip_col
        row.push(m[r][c])
      c += 1
    sub.push(row)
    r += 1
  sub

-> determinant(m)
  n = m.size
  if n == 1
    return m[0][0]
  if n == 2
    return m[0][0] * m[1][1] - m[0][1] * m[1][0]
  total = 0
  sign = 1
  c = 0
  while c < n
    total += sign * m[0][c] * determinant(minor_matrix(m, c))
    sign = -sign
    c += 1
  total

-> permanent(m)
  n = m.size
  if n == 1
    return m[0][0]
  total = 0
  c = 0
  while c < n
    total += m[0][c] * permanent(minor_matrix(m, c))
    c += 1
  total

a = [
  [1, 2, 3],
  [4, 5, 6],
  [7, 8, 9]
]
b = [
  [2, 9, 4],
  [7, 5, 3],
  [6, 1, 8]
]

<< "det(A) = [determinant(a)], perm(A) = [permanent(a)]"
<< "det(B) = [determinant(b)], perm(B) = [permanent(b)]"

## expect stdout
## det(A) = 0, perm(A) = 450
## det(B) = -360, perm(B) = 900
