# Identity matrix

-> identity_matrix(n)
  m = []
  r = 0
  while r < n
    row = []
    c = 0
    while c < n
      if r == c
        row.push(1)
      else
        row.push(0)
      c += 1
    m.push(row)
    r += 1
  m

mat = identity_matrix(4)
mat.each -> (row)
  << row.join(" ")

## expect stdout
## 1 0 0 0
## 0 1 0 0
## 0 0 1 0
## 0 0 0 1
