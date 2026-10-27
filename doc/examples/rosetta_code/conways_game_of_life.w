# Conway's Game of Life

-> step_life(grid, rows, cols)
  next_grid = []
  r = 0
  while r < rows
    row = []
    c = 0
    while c < cols
      neighbors = 0
      dr = -1
      while dr <= 1
        dc = -1
        while dc <= 1
          if dr != 0 || dc != 0
            nr = r + dr
            nc = c + dc
            if nr >= 0 && nr < rows && nc >= 0 && nc < cols
              neighbors += grid[nr][nc]
          dc += 1
        dr += 1
      alive = grid[r][c]
      if alive == 1 && (neighbors == 2 || neighbors == 3)
        row.push(1)
      elsif alive == 0 && neighbors == 3
        row.push(1)
      else
        row.push(0)
      c += 1
    next_grid.push(row)
    r += 1
  next_grid

-> print_grid(grid)
  grid.each -> (row)
    s = ""
    row.each -> (cell)
      if cell == 1
        s += "#"
      else
        s += "."
    << s

grid = [
  [0, 1, 0],
  [0, 1, 0],
  [0, 1, 0]
]

(0..2).each -> (gen)
  << "Gen [gen]:"
  print_grid(grid)
  grid = step_life(grid, 3, 3)

## expect stdout
## Gen 0:
## .#.
## .#.
## .#.
## Gen 1:
## ...
## ###
## ...
## Gen 2:
## .#.
## .#.
## .#.
