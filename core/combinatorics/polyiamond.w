# Polyiamonds: edge-connected sets of triangles in the triangular grid.
#
# Triangles are not lattice points — they come in two orientations, so the
# generic lattice-animal machinery does not apply. The clean model is the
# three-coordinate one: cut the plane by three families of parallel lines and
# name a triangle by the triple (a, b, c) of the strips containing it. Then
#
#   a + b + c = 1   upward triangles
#   a + b + c = 2   downward triangles
#
# and neighbours are exactly the triples differing by one in a single
# coordinate — an upward triangle (sum 1) touches the three downward ones
# obtained by adding 1 to one coordinate, and conversely.
#
# The symmetry falls out of the same picture. Permuting the three coordinates
# permutes the three line families, giving the six-element group S3; the
# complement `sigma(a, b, c) = (1 - a, 1 - b, 1 - c)` exchanges the two
# orientations and turns the plane by sixty degrees. Together they generate
# D6, of order 12, which is exactly the triangular lattice's point group.
# Translations are the triples summing to zero.
#
# Free polyiamond counts are OEIS A000577.

+ Polyiamond
  -> .cell_key(cell)
    "[cell[0]],[cell[1]],[cell[2]]"

  -> .key_of(cells)
    parts = []
    i = 0
    while i < cells.size
      parts.push(Polyiamond.cell_key(cells[i]))
      i += 1
    parts.join(";")

  -> .compare(a, b)
    i = 0
    while i < 3
      return a[i] <=> b[i] if a[i] != b[i]
      i += 1
    0

  # Translations are the vectors with coordinate sum zero, so shifting the
  # first two coordinates to a minimum of zero is a canonical choice.
  -> .normalize(cells)
    mina = cells[0][0]
    minb = cells[0][1]
    i = 1
    while i < cells.size
      mina = cells[i][0] if cells[i][0] < mina
      minb = cells[i][1] if cells[i][1] < minb
      i += 1
    out = []
    i = 0
    while i < cells.size
      out.push([cells[i][0] - mina, cells[i][1] - minb,
                cells[i][2] + mina + minb])
      i += 1
    out.sort ->(x, y)
      Polyiamond.compare(x, y)

  -> .permutations
    [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]

  # The twelve images under D6: six coordinate permutations, each optionally
  # composed with the orientation-reversing complement.
  -> .transform(cells, index)
    slot = index % 12
    slot += 12 if slot < 0
    perm = Polyiamond.permutations[slot % 6]
    flip = slot >= 6
    out = []
    i = 0
    while i < cells.size
      cell = cells[i]
      mapped = [cell[perm[0]], cell[perm[1]], cell[perm[2]]]
      mapped = [1 - mapped[0], 1 - mapped[1], 1 - mapped[2]] if flip
      out.push(mapped)
      i += 1
    out

  -> .key_less?(left, right)
    return left.size < right.size if left.size != right.size
    left < right

  -> .canonical_key(cells)
    best = nil
    i = 0
    while i < 12
      key = Polyiamond.key_of(Polyiamond.normalize(Polyiamond.transform(cells, i)))
      best = key if best == nil || Polyiamond.key_less?(key, best)
      i += 1
    best

  -> .neighbours(cell)
    total = cell[0] + cell[1] + cell[2]
    step = total == 1 ? 1 : 0 - 1
    [[cell[0] + step, cell[1], cell[2]],
     [cell[0], cell[1] + step, cell[2]],
     [cell[0], cell[1], cell[2] + step]]

  -> .fixed_cells(n)
    raise "cell count must be positive" if n < 1
    shapes = [[[1, 0, 0]]]
    k = 1
    while k < n
      seen = {}
      grown = []
      s = 0
      while s < shapes.size
        cells = shapes[s]
        occupied = {}
        c = 0
        while c < cells.size
          occupied[Polyiamond.cell_key(cells[c])] = true
          c += 1
        c = 0
        while c < cells.size
          options = Polyiamond.neighbours(cells[c])
          o = 0
          while o < options.size
            candidate_cell = options[o]
            o += 1
            next if occupied.key?(Polyiamond.cell_key(candidate_cell))
            candidate = []
            i = 0
            while i < cells.size
              candidate.push(cells[i])
              i += 1
            candidate.push(candidate_cell)
            normalized = Polyiamond.normalize(candidate)
            key = Polyiamond.key_of(normalized)
            next if seen.key?(key)
            seen[key] = true
            grown.push(normalized)
          c += 1
        s += 1
      shapes = grown
      k += 1
    shapes

  -> .free_cells(n)
    fixed = Polyiamond.fixed_cells(n)
    seen = {}
    out = []
    i = 0
    while i < fixed.size
      key = Polyiamond.canonical_key(fixed[i])
      if !seen.key?(key)
        seen[key] = true
        out.push(fixed[i])
      i += 1
    out

  -> .count_fixed(n)
    Polyiamond.fixed_cells(n).size

  -> .count_free(n)
    Polyiamond.free_cells(n).size
