# Periodic tilings, found constructively on a torus.
#
# A periodic tiling by copies of a shape is a translation lattice L together
# with K placements whose L-translates partition the plane — equivalently, K
# placements that tile the torus plane/L exactly. Finding one is a finite
# exact-cover problem, and any hit is a proof that the shape tiles: it catches
# the anisohedral periodic tilers that the boundary-word criteria miss. A miss
# proves nothing.
#
# Search order: K = 1, 2, ... up to `k_max`; for each K every sublattice of
# index N = K · |S| (in cells; the iamond grid counts two triangles per
# lattice unit) in Hermite normal form {(a, 0), (b, c)} with a c = N and
# 0 <= b < a; the identity copy at the origin is fixed and the remaining torus
# cells are covered exactly by non-self-overlapping placements.

+ PeriodicTiling
  # Hermite normal forms (a, b, c) of the index-n sublattices of Z^2.
  -> .lattices(n)
    out = []
    a = 1
    while a <= n
      if n % a == 0
        c = n / a
        b = 0
        while b < a
          out.push([a, b, c])
          b += 1
      a += 1
    out

  # Reduce a cell modulo step · {(a, 0), (b, c)}, keeping iamond residues.
  -> .reduce(cell, a, b, c, step)
    x = cell[0]
    y = cell[1]
    if step == 1
      k = PeriodicTiling.floor_div(y, c)
      yy = y - k * c
      xx = TilingGrid.pmod(x - k * b, a)
      return [xx, yy]
    rx = TilingGrid.pmod(x, step)
    ry = TilingGrid.pmod(y, step)
    bx = (x - rx) / step
    by = (y - ry) / step
    k = PeriodicTiling.floor_div(by, c)
    by = by - k * c
    bx = TilingGrid.pmod(bx - k * b, a)
    [bx * step + rx, by * step + ry]

  -> .floor_div(a, n)
    q = a / n
    q -= 1 if (a % n != 0) && ((a < 0) != (n < 0))
    q

  # A periodic tiling as {"k", "lattice": [a, b, c], "placements"}, or nil.
  # `placements` are [orientation, tx, ty] copies whose lattice translates
  # tile the plane.
  -> .find(shape, k_max = 8)
    grid = shape.grid
    tile = shape.cells
    n_cells = tile.size
    step = grid.id == "I" ? 3 : 1
    unit = grid.id == "I" ? 2 : 1
    k = 1
    while k <= k_max
      total = k * n_cells
      if total % unit == 0
        n = total / unit
        lattices = PeriodicTiling.lattices(n)
        li = 0
        while li < lattices.size
          a = lattices[li][0]
          b = lattices[li][1]
          c = lattices[li][2]
          li += 1
          found = PeriodicTiling.try_lattice(shape, grid, a, b, c, step, k, total)
          return found if found != nil
      k += 1
    nil

  -> .try_lattice(shape, grid, a, b, c, step, k, total)
    tile = shape.cells
    n_cells = tile.size
    base = {}
    i = 0
    while i < n_cells
      base[TilingGrid.cell_key(PeriodicTiling.reduce(tile[i], a, b, c, step))] = true
      i += 1
    return nil if base.keys.size != n_cells
    torus = []
    torus_index = {}
    xx = 0
    while xx < a
      yy = 0
      while yy < c
        rx = 0
        while rx < step
          cell = [xx * step + rx, yy * step + rx]
          if grid.cell_valid?(cell)
            torus.push(cell)
            torus_index[TilingGrid.cell_key(cell)] = torus.size
          rx += 1
        yy += 1
      xx += 1
    return nil if torus.size != total
    # Columns: torus cells not in the identity copy, primary.
    column = {}
    count = 0
    i = 0
    while i < torus.size
      key = TilingGrid.cell_key(torus[i])
      if !base.key?(key)
        count += 1
        column[key] = count
      i += 1
    return nil if count != total - n_cells
    if count == 0
      return { "k": k, "lattice": [a, b, c], "placements": [[0, 0, 0]] }
    cover = ExactCover.new(count, count)
    rows = []
    seen = {}
    si = 0
    while si < grid.orientation_count
      img = shape.image(si)
      ti = 0
      while ti < torus.size
        t = torus[ti]
        ti += 1
        tx = t[0] - img[0][0]
        ty = t[1] - img[0][1]
        next if !grid.translation_legal?(tx, ty)
        cols = []
        ok = true
        placed = {}
        j = 0
        while j < img.size && ok
          r = PeriodicTiling.reduce([img[j][0] + tx, img[j][1] + ty], a, b, c, step)
          rk = TilingGrid.cell_key(r)
          ok = false if placed.key?(rk) || base.key?(rk) || !column.key?(rk)
          if ok
            placed[rk] = true
            cols.push(column[rk])
          j += 1
        next if !ok
        sig = cols.sort ->(p, q) p <=> q
        sk = sig.join(",")
        next if seen.key?(sk)
        seen[sk] = true
        cover.add_row(cols)
        rows.push([si, tx, ty])
      si += 1
    return nil if rows.size < k - 1
    solution = cover.solve
    return nil if solution == nil || solution.size != k - 1
    placements = [[0, 0, 0]]
    i = 0
    while i < solution.size
      placements.push(rows[solution[i]])
      i += 1
    { "k": k, "lattice": [a, b, c], "placements": placements }

  # Re-check a reported tiling: the placements' lattice translates partition
  # the torus exactly.
  -> .valid?(shape, result)
    grid = shape.grid
    a = result["lattice"][0]
    b = result["lattice"][1]
    c = result["lattice"][2]
    step = grid.id == "I" ? 3 : 1
    covered = {}
    total = 0
    ps = result["placements"]
    i = 0
    while i < ps.size
      cells = shape.placed(ps[i][0], ps[i][1], ps[i][2])
      j = 0
      while j < cells.size
        k = TilingGrid.cell_key(PeriodicTiling.reduce(cells[j], a, b, c, step))
        return false if covered.key?(k)
        covered[k] = true
        total += 1
        j += 1
      i += 1
    unit = grid.id == "I" ? 2 : 1
    total == a * c * unit
