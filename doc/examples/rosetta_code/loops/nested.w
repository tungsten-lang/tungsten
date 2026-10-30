# Loops/Nested

grid = [
  [2, 12, 10, 4],
  [18, 11, 20, 15],
  [14, 6, 19, 8]
]

-> find_twenty(grid)
  r = 0
  while r < grid.size
    c = 0
    while c < grid[r].size
      val = grid[r][c]
      << val
      if val == 20
        return
      c += 1
    r += 1

find_twenty(grid)

## expect stdout
## 2
## 12
## 10
## 4
## 18
## 11
## 20
