# Dimer coverings: counting the ways to tile a region with dominoes.
#
# Kasteleyn's theorem is the classical result here — for a planar graph the
# number of perfect matchings equals the Pfaffian of a suitably signed
# adjacency matrix, turning an apparently exponential count into a
# determinant. This module reaches the same numbers by a transfer matrix over
# broken profiles, for two practical reasons: the arithmetic stays in exact
# integers (Kasteleyn's route runs through eigenvalues or large determinants),
# and it counts tilings of an *arbitrary* region, not just a rectangle, which
# is what pairs with polyomino work.
#
# The method sweeps cells in row-major order carrying a bitmask of the
# frontier: bit j records whether the cell one row ahead in column j has
# already been filled by a vertical domino dropped from the current row. At
# each cell either that bit is set (the cell is spoken for), or we place a
# horizontal domino into the next column, or a vertical one into the next row.
# Every tiling corresponds to exactly one path through these choices, so the
# accumulated count is exact.
#
# Cost is O(cells * 2^width), so keep the narrower side as the width.

+ DimerCovering
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  # Number of domino tilings of a width x height rectangle.
  -> .rectangle(width, height)
    if !DimerCovering.integer?(width) || !DimerCovering.integer?(height)
      raise "rectangle dimensions must be integers"
    raise "rectangle dimensions must be positive" if width < 1 || height < 1
    cells = []
    y = 0
    while y < height
      x = 0
      while x < width
        cells.push([x, y])
        x += 1
      y += 1
    DimerCovering.region(cells)

  # Number of domino tilings of an arbitrary set of cells. Cells are [x, y]
  # pairs; the region need not be simply connected or even connected.
  -> .region(cells)
    return 0 if cells.size % 2 == 1
    return 1 if cells.size == 0
    present = {}
    minx = cells[0][0]
    maxx = cells[0][0]
    miny = cells[0][1]
    maxy = cells[0][1]
    i = 0
    while i < cells.size
      x = cells[i][0]
      y = cells[i][1]
      present["[x],[y]"] = true
      minx = x if x < minx
      maxx = x if x > maxx
      miny = y if y < miny
      maxy = y if y > maxy
      i += 1
    width = maxx - minx + 1
    height = maxy - miny + 1
    raise "region too wide for the profile sweep (limit 22)" if width > 22
    size = 1
    b = 0
    while b < width
      size = size * 2
      b += 1
    # states[mask] = number of ways to reach this frontier
    states = []
    m = 0
    while m < size
      states.push(0)
      m += 1
    states[0] = 1
    y = 0
    while y < height
      x = 0
      while x < width
        occupied = present.key?("[minx + x],[miny + y]")
        bit = 1
        s = 0
        while s < x
          bit = bit * 2
          s += 1
        nxt = []
        m = 0
        while m < size
          nxt.push(0)
          m += 1
        m = 0
        while m < size
          count = states[m]
          m += 1
          next if count == 0
          mask = m - 1
          filled = (mask / bit) % 2 == 1
          if !occupied
            # A hole: it must not have been filled from above.
            nxt[mask] = nxt[mask] + count if !filled
            next
          if filled
            # Already covered by a vertical domino from the previous row.
            nxt[mask - bit] = nxt[mask - bit] + count
            next
          # Place a vertical domino, reserving the cell below.
          below = present.key?("[minx + x],[miny + y + 1]")
          nxt[mask + bit] = nxt[mask + bit] + count if below && y + 1 < height
          # Place a horizontal domino into the next column.
          if x + 1 < width && present.key?("[minx + x + 1],[miny + y]")
            right_bit = bit * 2
            if (mask / right_bit) % 2 == 0
              nxt[mask + right_bit] = nxt[mask + right_bit] + count
        states = nxt
        x += 1
      y += 1
    states[0]

  # Convenience: tilings of the region a polyomino occupies.
  -> .polyomino(shape)
    DimerCovering.region(shape.cells)

  # A region with an odd number of cells has no tiling; so does one whose two
  # colour classes differ in size, since every domino covers one of each.
  -> .colour_balanced?(cells)
    dark = 0
    light = 0
    i = 0
    while i < cells.size
      parity = (cells[i][0] + cells[i][1]) % 2
      parity += 2 if parity < 0
      if parity == 0
        dark += 1
      else
        light += 1
      i += 1
    dark == light
