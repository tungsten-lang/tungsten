# Magic squares of odd order

-> magic_square(n)
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
  r = 0
  c = n / 2
  num = 1
  while num <= n * n
    grid[r][c] = num
    next_r = (r - 1 + n) % n
    next_c = (c + 1) % n
    if grid[next_r][next_c] != 0
      r = (r + 1) % n
    else
      r = next_r
      c = next_c
    num += 1
  grid

sq = magic_square(5)
sq.each -> (row)
  << row.join(" ")
<< "Magic constant: [5 * (5 * 5 + 1) / 2]"

## expect stdout
## 17 24 1 8 15
## 23 5 7 14 16
## 4 6 13 20 22
## 10 12 19 21 3
## 11 18 25 2 9
## Magic constant: 65
