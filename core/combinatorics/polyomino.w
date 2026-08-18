# Enumeration of polyominoes by cell count.
#
# Three equivalence relations are in play, and each has its own count:
#
#   fixed      — up to translation only               (OEIS A001168)
#   one-sided  — up to translation and rotation       (OEIS A000988)
#   free       — up to translation, rotation, mirror  (OEIS A000105)
#
# The enumeration grows shapes by cell count: every polyomino of n cells is
# some polyomino of n-1 cells with one edge-adjacent cell added, so growing
# each (n-1)-shape at each of its empty neighbours and discarding repeats by
# normal form yields exactly the n-shapes. Deduplication uses the string
# normal form, so the cost is one hash probe per candidate.
#
# The hot paths work on raw [x, y] arrays rather than Polyomino objects:
# growth already guarantees connectivity, so re-validating it per candidate
# would be redundant work. Only the public entry points build objects.

+ PolyominoEnumeration
  -> .require_size(n)
    if !Polyomino.integer?(n) || n < 1
      raise "polyomino cell count must be a positive integer"
    n

  # ---- raw cell-list helpers ------------------------------------------

  -> .key_of(cells)
    normalized = Polyomino.normalize(cells)
    parts = []
    i = 0
    while i < normalized.size
      parts.push("[normalized[i][0]],[normalized[i][1]]")
      i += 1
    parts.join(";")

  -> .reflect_cells(cells)
    out = []
    i = 0
    while i < cells.size
      out.push([0 - cells[i][0], cells[i][1]])
      i += 1
    out

  -> .rotate_cells(cells)
    out = []
    i = 0
    while i < cells.size
      out.push([cells[i][1], 0 - cells[i][0]])
      i += 1
    out

  # Smallest key over a subgroup of D4: the 4 rotations, plus their mirrors
  # when `mirror` is true. That is the free normal form when mirrors count,
  # and the one-sided normal form when they do not.
  -> .canonical_key(cells, mirror)
    best = nil
    variant = cells
    i = 0
    while i < 4
      key = PolyominoEnumeration.key_of(variant)
      best = key if best == nil || PolyominoEnumeration.key_less?(key, best)
      variant = PolyominoEnumeration.rotate_cells(variant)
      i += 1
    if mirror
      variant = PolyominoEnumeration.reflect_cells(cells)
      i = 0
      while i < 4
        key = PolyominoEnumeration.key_of(variant)
        best = key if PolyominoEnumeration.key_less?(key, best)
        variant = PolyominoEnumeration.rotate_cells(variant)
        i += 1
    best

  -> .key_less?(left, right)
    return left.size < right.size if left.size != right.size
    left < right

  # ---- enumeration ----------------------------------------------------

  # All fixed polyominoes of `n` cells, as raw normalized cell lists.
  -> .fixed_cells(n)
    PolyominoEnumeration.require_size(n)
    shapes = [[[0, 0]]]
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
          occupied[Polyomino.cell_key(cells[c][0], cells[c][1])] = true
          c += 1
        c = 0
        while c < cells.size
          x = cells[c][0]
          y = cells[c][1]
          dx = [1, -1, 0, 0]
          dy = [0, 0, 1, -1]
          d = 0
          while d < 4
            nx = x + dx[d]
            ny = y + dy[d]
            d += 1
            next if occupied.key?(Polyomino.cell_key(nx, ny))
            candidate = []
            j = 0
            while j < cells.size
              candidate.push([cells[j][0], cells[j][1]])
              j += 1
            candidate.push([nx, ny])
            key = PolyominoEnumeration.key_of(candidate)
            next if seen.key?(key)
            seen[key] = true
            grown.push(Polyomino.normalize(candidate))
          c += 1
        s += 1
      shapes = grown
      k += 1
    shapes

  # Fixed shapes reduced modulo the given symmetry: `mirror` true gives the
  # free polyominoes, false gives the one-sided ones.
  -> .reduced_cells(n, mirror)
    fixed = PolyominoEnumeration.fixed_cells(n)
    seen = {}
    out = []
    i = 0
    while i < fixed.size
      key = PolyominoEnumeration.canonical_key(fixed[i], mirror)
      if !seen.key?(key)
        seen[key] = true
        out.push(fixed[i])
      i += 1
    out

  -> .wrap(cells_list)
    out = []
    i = 0
    while i < cells_list.size
      out.push(Polyomino.new(cells_list[i]))
      i += 1
    out

  -> .fixed(n)
    PolyominoEnumeration.wrap(PolyominoEnumeration.fixed_cells(n))

  -> .free(n)
    PolyominoEnumeration.wrap(PolyominoEnumeration.reduced_cells(n, true))

  -> .one_sided(n)
    PolyominoEnumeration.wrap(PolyominoEnumeration.reduced_cells(n, false))

  -> .count_fixed(n)
    PolyominoEnumeration.fixed_cells(n).size

  -> .count_free(n)
    PolyominoEnumeration.reduced_cells(n, true).size

  -> .count_one_sided(n)
    PolyominoEnumeration.reduced_cells(n, false).size

  # Every free polyomino of 1..n cells — the piece catalogue a packing
  # problem draws from.
  -> .free_upto(n)
    PolyominoEnumeration.require_size(n)
    out = []
    k = 1
    while k <= n
      PolyominoEnumeration.free(k).each ->(shape)
        out.push(shape)
      k += 1
    out
