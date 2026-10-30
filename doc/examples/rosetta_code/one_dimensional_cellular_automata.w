# One-dimensional cellular automata

-> evolve(cells)
  n = cells.size
  next_cells = []
  i = 0
  while i < n
    left = 0
    if i > 0
      left = cells[i - 1]
    mid = cells[i]
    right = 0
    if i + 1 < n
      right = cells[i + 1]
    if left + mid + right == 2
      next_cells.push(1)
    else
      next_cells.push(0)
    i += 1
  next_cells

-> format_cells(cells)
  s = ""
  cells.each -> (c)
    if c == 1
      s += "#"
    else
      s += "_"
  s

cells = [0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0]
(0..9).each -> (gen)
  << "Gen [gen]: [format_cells(cells)]"
  cells = evolve(cells)

## expect stdout
## Gen 0: _###_##_#_#_#_#__#__
## Gen 1: _#_#####_#_#_#______
## Gen 2: __##___##_#_#_______
## Gen 3: __##___###_#________
## Gen 4: __##___#_##_________
## Gen 5: __##____###_________
## Gen 6: __##____#_#_________
## Gen 7: __##_____#__________
## Gen 8: __##________________
## Gen 9: __##________________
