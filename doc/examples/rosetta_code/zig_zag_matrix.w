# Zig-zag matrix

-> zig_zag(n)
  grid = []
  r = 0
  while r < n
    row = []
    c = 0
    while c < n
      row.push(0)
      c += 1
    grid.push(row)
    r += 1
  i = 0
  j = 0
  d = -1
  val = 0
  while val < n * n
    grid[i][j] = val
    val += 1
    if d == -1
      if j == n - 1
        i += 1
        d = 1
      elsif i == 0
        j += 1
        d = 1
      else
        i -= 1
        j += 1
    else
      if i == n - 1
        j += 1
        d = -1
      elsif j == 0
        i += 1
        d = -1
      else
        i += 1
        j -= 1
  grid

m = zig_zag(5)
m.each -> (row)
  << row.join(" ")

## expect stdout
## 0 1 5 6 14
## 2 4 7 13 15
## 3 8 12 16 21
## 9 11 17 20 22
## 10 18 19 23 24
