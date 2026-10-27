# Langton's ant

-> run_ant(size, steps)
  grid = []
  r = 0
  while r < size
    row = []
    c = 0
    while c < size
      row.push(0)
      c += 1
    grid.push(row)
    r += 1
  x = size / 2
  y = size / 2
  dir = 0
  dx = [0, 1, 0, -1]
  dy = [-1, 0, 1, 0]
  s = 0
  while s < steps
    if grid[y][x] == 0
      dir = (dir + 1) % 4
      grid[y][x] = 1
    else
      dir = (dir + 3) % 4
      grid[y][x] = 0
    x += dx[dir]
    y += dy[dir]
    s += 1
  grid

grid = run_ant(7, 20)
grid.each -> (row)
  line = ""
  row.each -> (cell)
    if cell == 1
      line += "#"
    else
      line += "."
  << line

## expect stdout
## .......
## .......
## ..##...
## .#..#..
## ..#.#..
## .......
## .......
