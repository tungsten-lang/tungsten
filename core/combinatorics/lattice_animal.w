# Lattice animals: finite edge-connected sets of cells in any lattice.
#
# A polyomino is the square-lattice case, a polyhex the triangular-lattice
# case, a polycube the cubic one. They differ only in which steps join
# neighbouring cells and which point group acts, so one enumeration serves all
# three: grow shapes a cell at a time and deduplicate by normal form.
#
# `fixed` counts up to translation, `free` up to the lattice's full point
# group. The counts are classical:
#
#   square  fixed A001168, free A000105
#   hex     fixed A001207, free A000228
#   cubic   fixed A001931, free A038119 (A000162 up to rotation only)

+ Lattice
  -> new(@steps, @group, @name) ro

  # The square lattice: four edge neighbours, symmetry D4.
  -> .square
    Lattice.new([[1, 0], [0 - 1, 0], [0, 1], [0, 0 - 1]],
                LatticeSymmetry.square, "square")

  # The triangular lattice in axial coordinates — the adjacency of hexagonal
  # cells, six neighbours, symmetry D6.
  -> .hexagonal
    Lattice.new([[1, 0], [0 - 1, 0], [0, 1], [0, 0 - 1], [1, 0 - 1], [0 - 1, 1]],
                LatticeSymmetry.hexagonal, "hexagonal")

  # The cubic lattice: six face neighbours, symmetry the 48-element group.
  -> .cubic
    Lattice.new([[1, 0, 0], [0 - 1, 0, 0], [0, 1, 0], [0, 0 - 1, 0],
                 [0, 0, 1], [0, 0, 0 - 1]],
                LatticeSymmetry.cubic, "cubic")

  # The cubic lattice counted up to rotation only. Mirror images of a chiral
  # polycube are then distinct, which is the convention A000162 uses; the
  # reflection-allowing count is A038119. The two first differ at four cells,
  # where one chiral pair merges: 8 becomes 7.
  -> .cubic_chiral
    Lattice.new([[1, 0, 0], [0 - 1, 0, 0], [0, 1, 0], [0, 0 - 1, 0],
                 [0, 0, 1], [0, 0, 0 - 1]],
                LatticeSymmetry.cubic_rotations, "cubic_chiral")

  -> dimension
    @steps[0].size

+ LatticeAnimal
  -> .key_of(cells)
    parts = []
    i = 0
    while i < cells.size
      parts.push(LatticeAnimal.cell_key(cells[i]))
      i += 1
    parts.join(";")

  -> .cell_key(cell)
    parts = []
    i = 0
    while i < cell.size
      parts.push("[cell[i]]")
      i += 1
    parts.join(",")

  -> .compare_cells(a, b)
    i = 0
    while i < a.size
      return a[i] <=> b[i] if a[i] != b[i]
      i += 1
    0

  # Translate so the minimum along every axis is zero, then sort.
  -> .normalize(cells)
    d = cells[0].size
    mins = []
    j = 0
    while j < d
      m = cells[0][j]
      i = 1
      while i < cells.size
        m = cells[i][j] if cells[i][j] < m
        i += 1
      mins.push(m)
      j += 1
    shifted = []
    i = 0
    while i < cells.size
      cell = []
      j = 0
      while j < d
        cell.push(cells[i][j] - mins[j])
        j += 1
      shifted.push(cell)
      i += 1
    shifted.sort ->(a, b)
      LatticeAnimal.compare_cells(a, b)

  -> .key_less?(left, right)
    return left.size < right.size if left.size != right.size
    left < right

  # Least normal form over the whole point group — the free animal's identity.
  -> .canonical_key(cells, group)
    best = nil
    elements = group.elements
    g = 0
    while g < elements.size
      image = []
      i = 0
      while i < cells.size
        image.push(LatticeSymmetry.apply(elements[g], cells[i]))
        i += 1
      key = LatticeAnimal.key_of(LatticeAnimal.normalize(image))
      best = key if best == nil || LatticeAnimal.key_less?(key, best)
      g += 1
    best

  # All animals of `n` cells up to translation, as normalized cell lists.
  -> .fixed_cells(n, lattice)
    raise "cell count must be a positive integer" if n < 1
    d = lattice.dimension
    origin = []
    j = 0
    while j < d
      origin.push(0)
      j += 1
    shapes = [[origin]]
    steps = lattice.steps
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
          occupied[LatticeAnimal.cell_key(cells[c])] = true
          c += 1
        c = 0
        while c < cells.size
          st = 0
          while st < steps.size
            neighbour = []
            j = 0
            while j < d
              neighbour.push(cells[c][j] + steps[st][j])
              j += 1
            st += 1
            next if occupied.key?(LatticeAnimal.cell_key(neighbour))
            candidate = []
            i = 0
            while i < cells.size
              candidate.push(cells[i])
              i += 1
            candidate.push(neighbour)
            normalized = LatticeAnimal.normalize(candidate)
            key = LatticeAnimal.key_of(normalized)
            next if seen.key?(key)
            seen[key] = true
            grown.push(normalized)
          c += 1
        s += 1
      shapes = grown
      k += 1
    shapes

  -> .free_cells(n, lattice)
    fixed = LatticeAnimal.fixed_cells(n, lattice)
    seen = {}
    out = []
    i = 0
    while i < fixed.size
      key = LatticeAnimal.canonical_key(fixed[i], lattice.group)
      if !seen.key?(key)
        seen[key] = true
        out.push(fixed[i])
      i += 1
    out

  -> .count_fixed(n, lattice)
    LatticeAnimal.fixed_cells(n, lattice).size

  -> .count_free(n, lattice)
    LatticeAnimal.free_cells(n, lattice).size
