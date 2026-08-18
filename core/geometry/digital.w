# Digital geometry: the primitives for reasoning about shapes made of cells.
#
# Continuous geometry asks where a line passes; digital geometry asks which
# cells it lights up. The answers differ in kind, and the classical algorithms
# here — Bresenham's line and the midpoint circle — are exactly the ones that
# keep the arithmetic in integers, so a rasterised shape is exact rather than
# rounded.
#
# The rest is the morphology and connectivity vocabulary that shape analysis
# rests on: 4- and 8-neighbourhoods, connected components, dilation and
# erosion, and distance transforms under the L1 and L-infinity metrics (the
# lattice metrics matching those two neighbourhoods).

+ DigitalGeometry
  -> .cell_key(x, y)
    "[x],[y]"

  -> .index(cells)
    seen = {}
    i = 0
    while i < cells.size
      seen[DigitalGeometry.cell_key(cells[i][0], cells[i][1])] = true
      i += 1
    seen

  # The four edge neighbours, or the eight that include diagonals.
  -> .neighbour_steps(connectivity)
    if connectivity == 4
      return [[1, 0], [0 - 1, 0], [0, 1], [0, 0 - 1]]
    if connectivity == 8
      return [[1, 0], [0 - 1, 0], [0, 1], [0, 0 - 1],
              [1, 1], [1, 0 - 1], [0 - 1, 1], [0 - 1, 0 - 1]]
    raise "connectivity must be 4 or 8"

  # Bresenham's line: the cells a segment from (x0, y0) to (x1, y1) passes
  # through, endpoints included, chosen by integer error accumulation so no
  # rounding ever enters.
  -> .line(x0, y0, x1, y1)
    out = []
    x = x0
    y = y0
    dx = x1 - x0
    dx = 0 - dx if dx < 0
    dy = y1 - y0
    dy = 0 - dy if dy < 0
    sx = x0 < x1 ? 1 : 0 - 1
    sy = y0 < y1 ? 1 : 0 - 1
    err = dx - dy
    running = true
    while running
      out.push([x, y])
      if x == x1 && y == y1
        running = false
      else
        e2 = 2 * err
        if e2 > 0 - dy
          err -= dy
          x += sx
        if e2 < dx
          err += dx
          y += sy
    out

  # Midpoint circle: the cells on a discrete circle of the given radius,
  # again by integer decision variable only.
  -> .circle(cx, cy, radius)
    raise "radius must be nonnegative" if radius < 0
    return [[cx, cy]] if radius == 0
    seen = {}
    out = []
    x = radius
    y = 0
    err = 1 - radius
    while x >= y
      octants = [[cx + x, cy + y], [cx + y, cy + x], [cx - y, cy + x],
                 [cx - x, cy + y], [cx - x, cy - y], [cx - y, cy - x],
                 [cx + y, cy - x], [cx + x, cy - y]]
      i = 0
      while i < octants.size
        key = DigitalGeometry.cell_key(octants[i][0], octants[i][1])
        if !seen.key?(key)
          seen[key] = true
          out.push(octants[i])
        i += 1
      y += 1
      if err < 0
        err += 2 * y + 1
      else
        x -= 1
        err += 2 * (y - x) + 1
    out

  # Connected components under the given connectivity, as arrays of cells.
  -> .connected_components(cells, connectivity)
    present = DigitalGeometry.index(cells)
    steps = DigitalGeometry.neighbour_steps(connectivity)
    seen = {}
    out = []
    i = 0
    while i < cells.size
      start = cells[i]
      i += 1
      key = DigitalGeometry.cell_key(start[0], start[1])
      next if seen.key?(key)
      seen[key] = true
      component = [start]
      head = 0
      while head < component.size
        cell = component[head]
        head += 1
        s = 0
        while s < steps.size
          nx = cell[0] + steps[s][0]
          ny = cell[1] + steps[s][1]
          s += 1
          nkey = DigitalGeometry.cell_key(nx, ny)
          next if !present.key?(nkey) || seen.key?(nkey)
          seen[nkey] = true
          component.push([nx, ny])
      out.push(component)
    out

  -> .connected?(cells, connectivity)
    return true if cells.size <= 1
    DigitalGeometry.connected_components(cells, connectivity).size == 1

  # Morphological dilation: the region grown by one cell in every direction of
  # the neighbourhood.
  -> .dilate(cells, connectivity)
    steps = DigitalGeometry.neighbour_steps(connectivity)
    seen = {}
    out = []
    i = 0
    while i < cells.size
      candidates = [[cells[i][0], cells[i][1]]]
      s = 0
      while s < steps.size
        candidates.push([cells[i][0] + steps[s][0], cells[i][1] + steps[s][1]])
        s += 1
      c = 0
      while c < candidates.size
        key = DigitalGeometry.cell_key(candidates[c][0], candidates[c][1])
        if !seen.key?(key)
          seen[key] = true
          out.push(candidates[c])
        c += 1
      i += 1
    out

  # Morphological erosion: the cells all of whose neighbours are also present.
  -> .erode(cells, connectivity)
    present = DigitalGeometry.index(cells)
    steps = DigitalGeometry.neighbour_steps(connectivity)
    out = []
    i = 0
    while i < cells.size
      keep = true
      s = 0
      while s < steps.size
        nx = cells[i][0] + steps[s][0]
        ny = cells[i][1] + steps[s][1]
        keep = false if !present.key?(DigitalGeometry.cell_key(nx, ny))
        s += 1
      out.push([cells[i][0], cells[i][1]]) if keep
      i += 1
    out

  # Cells of the region that touch the background.
  -> .boundary(cells, connectivity)
    present = DigitalGeometry.index(cells)
    steps = DigitalGeometry.neighbour_steps(connectivity)
    out = []
    i = 0
    while i < cells.size
      edge = false
      s = 0
      while s < steps.size
        nx = cells[i][0] + steps[s][0]
        ny = cells[i][1] + steps[s][1]
        edge = true if !present.key?(DigitalGeometry.cell_key(nx, ny))
        s += 1
      out.push([cells[i][0], cells[i][1]]) if edge
      i += 1
    out

  # Distance from each cell to the nearest background cell, by multi-source
  # breadth-first search from the boundary outward. Connectivity 4 gives the
  # L1 (taxicab) metric, connectivity 8 the L-infinity (chessboard) one.
  # Returns a hash from "x,y" to distance; a cell on the border has distance 1.
  -> .distance_transform(cells, connectivity)
    present = DigitalGeometry.index(cells)
    steps = DigitalGeometry.neighbour_steps(connectivity)
    distance = {}
    frontier = []
    i = 0
    while i < cells.size
      edge = false
      s = 0
      while s < steps.size
        nx = cells[i][0] + steps[s][0]
        ny = cells[i][1] + steps[s][1]
        edge = true if !present.key?(DigitalGeometry.cell_key(nx, ny))
        s += 1
      if edge
        distance[DigitalGeometry.cell_key(cells[i][0], cells[i][1])] = 1
        frontier.push(cells[i])
      i += 1
    head = 0
    while head < frontier.size
      cell = frontier[head]
      head += 1
      here = distance[DigitalGeometry.cell_key(cell[0], cell[1])]
      s = 0
      while s < steps.size
        nx = cell[0] + steps[s][0]
        ny = cell[1] + steps[s][1]
        s += 1
        key = DigitalGeometry.cell_key(nx, ny)
        next if !present.key?(key) || distance.key?(key)
        distance[key] = here + 1
        frontier.push([nx, ny])
    distance

  # Largest distance-transform value: the radius of the biggest ball the
  # region contains.
  -> .inradius(cells, connectivity)
    distance = DigitalGeometry.distance_transform(cells, connectivity)
    best = 0
    i = 0
    while i < cells.size
      v = distance.fetch(DigitalGeometry.cell_key(cells[i][0], cells[i][1]), 0)
      best = v if v > best
      i += 1
    best
