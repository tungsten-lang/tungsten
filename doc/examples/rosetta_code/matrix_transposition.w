# Matrix transposition

-> transpose(m)
  rows = m.size
  cols = m[0].size
  out = []
  c = 0
  while c < cols
    row = []
    r = 0
    while r < rows
      row.push(m[r][c])
      r += 1
    out.push(row)
    c += 1
  out

m = [
  [1, 2, 3],
  [4, 5, 6]
]
t = transpose(m)
t.each -> (row)
  << row

## expect stdout
## [1, 4]
## [2, 5]
## [3, 6]
