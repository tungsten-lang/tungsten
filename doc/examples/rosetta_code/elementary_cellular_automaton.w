# Elementary cellular automaton

-> rule_step(cells, rule)
  n = cells.size
  next_cells = []
  i = 0
  while i < n
    left = cells[(i - 1 + n) % n]
    mid = cells[i]
    right = cells[(i + 1) % n]
    pattern = (left << 2) + (mid << 1) + right
    bit = (rule >> pattern) & 1
    next_cells.push(bit)
    i += 1
  next_cells

-> render_cells(cells)
  s = ""
  cells.each -> (c)
    if c == 1
      s += "#"
    else
      s += "."
  s

cells = [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
(0..7).each -> (_)
  << render_cells(cells)
  cells = rule_step(cells, 90)

## expect stdout
## .......#.......
## ......#.#......
## .....#...#.....
## ....#.#.#.#....
## ...#.......#...
## ..#.#.....#.#..
## .#...#...#...#.
## #.#.#.#.#.#.#.#
