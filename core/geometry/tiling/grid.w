# Polyform grids for tiling theory: the square, hexagonal and triangular
# (iamond) grids in one object each, with the data that Heesch-number and
# tiling questions need and nothing else — cell adjacency, the point group as
# affine maps, translation legality, canonical forms, holes.
#
# Coordinates follow Craig Kaplan's heesch-sat, so the published Heesch
# census files parse directly:
#
#   square  (x, y) is the unit cell; 8 orientations (D4).
#   hex     axial (x, y); the six neighbours are the six edge neighbours, and
#           a shared boundary point is always a shared edge; 12 orientations
#           (D6).
#   iamond  triangles are the points (x, y) with x ≡ y (mod 3): x ≡ 0 is an
#           upward triangle, x ≡ 1 a downward one. Legal translations are
#           ≡ (0, 0) mod 3 componentwise. Six of the twelve orientations swap
#           the two classes and carry the affine offset (1, 1).
#
# Two adjacency relations matter. Edge adjacency defines connectivity and
# holes. Contact adjacency — sharing at least a boundary point — is what a
# corona is built from: a copy in corona k touches the previous patch when
# some cell of it is a contact neighbour of the patch. On the square grid
# contact means 8 neighbours, on the hex grid the same 6, on the iamond grid
# 12 (three across edges, nine across corners).
#
# An orientation is stored as [a, b, c, d, e, f] and acts by
# x' = a x + b y + c, y' = d x + e y + f — the transform printed as
# <a,b,c,d,e,f> in heesch-sat witness files. Index 0 is always the identity.

+ TilingGrid
  -> new(@id, @name, @edge_up, @edge_down, @contact_up, @contact_down, @orientations, @flood_pad) ro

  -> .square
    edge = [[0, -1], [-1, 0], [1, 0], [0, 1]]
    contact = [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]]
    orientations = [[1, 0, 0, 0, 1, 0], [0, -1, 0, 1, 0, 0], [-1, 0, 0, 0, -1, 0], [0, 1, 0, -1, 0, 0],
                    [-1, 0, 0, 0, 1, 0], [0, -1, 0, -1, 0, 0], [1, 0, 0, 0, -1, 0], [0, 1, 0, 1, 0, 0]]
    TilingGrid.new("O", "square", edge, edge, contact, contact, orientations, 1)

  -> .hexagonal
    steps = [[0, -1], [0, 1], [1, 0], [-1, 0], [1, -1], [-1, 1]]
    orientations = [[1, 0, 0, 0, 1, 0], [0, -1, 0, 1, 1, 0], [-1, -1, 0, 1, 0, 0], [-1, 0, 0, 0, -1, 0],
                    [0, 1, 0, -1, -1, 0], [1, 1, 0, -1, 0, 0], [0, 1, 0, 1, 0, 0], [-1, 0, 0, 1, 1, 0],
                    [-1, -1, 0, 0, 1, 0], [0, -1, 0, -1, 0, 0], [1, 0, 0, -1, -1, 0], [1, 1, 0, 0, -1, 0]]
    TilingGrid.new("H", "hexagonal", steps, steps, steps, steps, orientations, 1)

  -> .iamond
    edge_up = [[1, 1], [-2, 1], [1, -2]]
    edge_down = [[-1, -1], [2, -1], [-1, 2]]
    contact_up = [[3, 0], [0, 3], [-3, 3], [-3, 0], [0, -3], [3, -3],
                  [1, 1], [-2, 4], [-2, 1], [-2, -2], [1, -2], [4, -2]]
    contact_down = [[3, 0], [0, 3], [-3, 3], [-3, 0], [0, -3], [3, -3],
                    [2, 2], [2, -1], [2, -4], [-1, -1], [-4, 2], [-1, 2]]
    orientations = [[1, 0, 0, 0, 1, 0], [-1, -1, 0, 1, 0, 0], [0, 1, 0, -1, -1, 0], [1, 0, 0, -1, -1, 0],
                    [0, 1, 0, 1, 0, 0], [-1, -1, 0, 0, 1, 0], [0, -1, 1, -1, 0, 1], [-1, 0, 1, 1, 1, 1],
                    [1, 1, 1, 0, -1, 1], [1, 1, 1, -1, 0, 1], [-1, 0, 1, 0, -1, 1], [0, -1, 1, 1, 1, 1]]
    TilingGrid.new("I", "iamond", edge_up, edge_down, contact_up, contact_down, orientations, 6)

  # The grid named by a heesch-sat grid letter: O, H or I.
  -> .for(letter)
    return TilingGrid.square if letter == "O"
    return TilingGrid.hexagonal if letter == "H"
    return TilingGrid.iamond if letter == "I"
    raise "unknown polyform grid [letter]"

  # ---- arithmetic helpers ---------------------------------------------

  # Modulo with a nonnegative result, whatever the sign of the dividend.
  -> .pmod(a, n)
    ((a % n) + n) % n

  -> .cell_key(cell)
    "[cell[0]],[cell[1]]"

  -> .compare(a, b)
    return a[0] <=> b[0] if a[0] != b[0]
    a[1] <=> b[1]

  -> .sort_cells(cells)
    cells.sort ->(a, b)
      TilingGrid.compare(a, b)

  # Membership hash: key -> true.
  -> .index(cells)
    present = {}
    i = 0
    while i < cells.size
      present[TilingGrid.cell_key(cells[i])] = true
      i += 1
    present

  -> .key(cells)
    sorted = TilingGrid.sort_cells(cells)
    parts = []
    i = 0
    while i < sorted.size
      parts.push(TilingGrid.cell_key(sorted[i]))
      i += 1
    parts.join(";")

  -> .offset_all(cell, offsets)
    out = []
    i = 0
    while i < offsets.size
      out.push([cell[0] + offsets[i][0], cell[1] + offsets[i][1]])
      i += 1
    out

  # ---- cells and adjacency ---------------------------------------------

  -> up?(cell)
    return true if @id != "I"
    TilingGrid.pmod(cell[0], 3) == 0

  -> cell_valid?(cell)
    return true if @id != "I"
    r = TilingGrid.pmod(cell[0], 3)
    r == TilingGrid.pmod(cell[1], 3) && r <= 1

  -> translation_legal?(dx, dy)
    return true if @id != "I"
    TilingGrid.pmod(dx, 3) == 0 && TilingGrid.pmod(dy, 3) == 0

  -> edge_neighbours(cell)
    TilingGrid.offset_all(cell, up?(cell) ? @edge_up : @edge_down)

  -> contact_neighbours(cell)
    TilingGrid.offset_all(cell, up?(cell) ? @contact_up : @contact_down)

  -> edge_degree
    @edge_up.size

  -> contact_degree
    @contact_up.size

  # Contact neighbours of a cell set that are not in the set — the halo.
  # For a patch this is exactly the set of cells its next corona must fill.
  -> halo(cells)
    present = TilingGrid.index(cells)
    seen = {}
    out = []
    i = 0
    while i < cells.size
      nbs = contact_neighbours(cells[i])
      j = 0
      while j < nbs.size
        k = TilingGrid.cell_key(nbs[j])
        if !present.key?(k) && !seen.key?(k)
          seen[k] = true
          out.push(nbs[j])
        j += 1
      i += 1
    TilingGrid.sort_cells(out)

  # Do two disjoint cell sets share a contact?
  -> touches?(a, b)
    small = a
    big = b
    if b.size < a.size
      small = b
      big = a
    present = TilingGrid.index(big)
    i = 0
    while i < small.size
      nbs = contact_neighbours(small[i])
      j = 0
      while j < nbs.size
        return true if present.key?(TilingGrid.cell_key(nbs[j]))
        j += 1
      i += 1
    false

  -> connected?(cells)
    return true if cells.size == 0
    present = TilingGrid.index(cells)
    seen = {}
    seen[TilingGrid.cell_key(cells[0])] = true
    stack = [cells[0]]
    count = 1
    while stack.size > 0
      c = stack.pop
      nbs = edge_neighbours(c)
      j = 0
      while j < nbs.size
        k = TilingGrid.cell_key(nbs[j])
        if present.key?(k) && !seen.key?(k)
          seen[k] = true
          count += 1
          stack.push(nbs[j])
        j += 1
    count == cells.size

  # Empty valid cells enclosed by `cells`: pad the bounding box, flood the
  # complement inward from the whole padding ring by edge adjacency, and
  # report every empty valid cell the flood could not reach.
  -> holes(cells)
    return [] if cells.size == 0
    present = TilingGrid.index(cells)
    x0 = cells[0][0]
    x1 = x0
    y0 = cells[0][1]
    y1 = y0
    i = 1
    while i < cells.size
      x0 = cells[i][0] if cells[i][0] < x0
      x1 = cells[i][0] if cells[i][0] > x1
      y0 = cells[i][1] if cells[i][1] < y0
      y1 = cells[i][1] if cells[i][1] > y1
      i += 1
    x0 -= @flood_pad
    x1 += @flood_pad
    y0 -= @flood_pad
    y1 += @flood_pad
    reached = {}
    stack = []
    x = x0
    while x <= x1
      ys = [y0, y1]
      t = 0
      while t < 2
        c = [x, ys[t]]
        k = TilingGrid.cell_key(c)
        if cell_valid?(c) && !present.key?(k) && !reached.key?(k)
          reached[k] = true
          stack.push(c)
        t += 1
      x += 1
    y = y0
    while y <= y1
      xs = [x0, x1]
      t = 0
      while t < 2
        c = [xs[t], y]
        k = TilingGrid.cell_key(c)
        if cell_valid?(c) && !present.key?(k) && !reached.key?(k)
          reached[k] = true
          stack.push(c)
        t += 1
      y += 1
    while stack.size > 0
      c = stack.pop
      nbs = edge_neighbours(c)
      j = 0
      while j < nbs.size
        n = nbs[j]
        j += 1
        next if n[0] < x0 || n[0] > x1 || n[1] < y0 || n[1] > y1
        k = TilingGrid.cell_key(n)
        next if present.key?(k) || reached.key?(k)
        reached[k] = true
        stack.push(n)
    out = []
    x = x0 + 1
    while x < x1
      y = y0 + 1
      while y < y1
        c = [x, y]
        k = TilingGrid.cell_key(c)
        out.push(c) if cell_valid?(c) && !present.key?(k) && !reached.key?(k)
        y += 1
      x += 1
    out

  -> hole_free?(cells)
    holes(cells).size == 0

  # ---- the point group ---------------------------------------------------

  -> orientation_count
    @orientations.size

  -> orientation(index)
    @orientations[index]

  -> .transform(xf, cell)
    [xf[0] * cell[0] + xf[1] * cell[1] + xf[2], xf[3] * cell[0] + xf[4] * cell[1] + xf[5]]

  -> .transform_all(xf, cells)
    out = []
    i = 0
    while i < cells.size
      out.push(TilingGrid.transform(xf, cells[i]))
      i += 1
    out

  -> apply(index, cell)
    TilingGrid.transform(@orientations[index], cell)

  -> apply_all(index, cells)
    TilingGrid.transform_all(@orientations[index], cells)

  # Index of the orientation with this linear part, or -1.
  -> orientation_of_linear(a, b, d, e)
    i = 0
    while i < @orientations.size
      o = @orientations[i]
      return i if o[0] == a && o[1] == b && o[3] == d && o[4] == e
      i += 1
    0 - 1

  # Is [a, b, c, d, e, f] a genuine motion of this grid? The linear part must
  # be one of the orientations (det ±1 is not enough: a shear is rejected) and
  # the residual translation must be on the lattice.
  -> transform_legal?(xf)
    i = orientation_of_linear(xf[0], xf[1], xf[3], xf[4])
    return false if i < 0
    o = @orientations[i]
    translation_legal?(xf[2] - o[2], xf[5] - o[5])

  -> determinant(xf)
    xf[0] * xf[4] - xf[1] * xf[3]

  -> reflection?(xf)
    determinant(xf) < 0

  # Translate so the minimum x and y are zero — on the iamond grid by
  # multiples of three, so residues are preserved — and sort.
  -> normalize(cells)
    mx = cells[0][0]
    my = cells[0][1]
    i = 1
    while i < cells.size
      mx = cells[i][0] if cells[i][0] < mx
      my = cells[i][1] if cells[i][1] < my
      i += 1
    dx = 0 - mx
    dy = 0 - my
    if @id == "I"
      dx = 0 - (mx - TilingGrid.pmod(mx, 3))
      dy = 0 - (my - TilingGrid.pmod(my, 3))
    out = []
    i = 0
    while i < cells.size
      out.push([cells[i][0] + dx, cells[i][1] + dy])
      i += 1
    TilingGrid.sort_cells(out)

  -> normal_key(cells)
    TilingGrid.key(normalize(cells))

  # The least normal form over the point group and the index of an
  # orientation attaining it: [cells, index].
  -> canonical(cells)
    best = nil
    best_key = nil
    best_index = 0
    i = 0
    while i < @orientations.size
      image = normalize(apply_all(i, cells))
      key = TilingGrid.key(image)
      if best == nil || TilingGrid.key_less?(key, best_key)
        best = image
        best_key = key
        best_index = i
      i += 1
    [best, best_index]

  -> canonical_key(cells)
    TilingGrid.key(canonical(cells)[0])

  -> .key_less?(left, right)
    return left.size < right.size if left.size != right.size
    left < right

  # Number of orientations fixing the shape up to translation.
  -> symmetry_order(cells)
    base = normal_key(cells)
    count = 0
    i = 0
    while i < @orientations.size
      count += 1 if normal_key(apply_all(i, cells)) == base
      i += 1
    count
