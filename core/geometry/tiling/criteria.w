# Boundary words and the classical sufficient conditions for tiling.
#
# The outer boundary of a hole-free polyform, walked counterclockwise with
# the interior on the left, is a cyclic word over the grid's edge directions
# — four on the square grid, six on the hexagonal and iamond grids — indexed
# so that the opposite direction is d + n/2 (mod n). Two factorization
# criteria then decide tiling by translations, or by translations and half
# turns, without any search over placements:
#
#   translation (Beauquier–Nivat)  W = X Y Z X̂ Ŷ Ẑ, where X̂ is X walked
#                                   backwards: reversed, every letter replaced
#                                   by its opposite. Up to two factors empty.
#   Conway                          W = A B C D E F with D = Â and B, C, E, F
#                                   each a palindrome (a run symmetric under a
#                                   half turn about its midpoint reads the
#                                   same backwards). Some factors may be empty.
#
# Both are sufficient, never necessary: rotation-only and anisohedral tilers
# fail them, so `false` means undecided. Both are O(n^3) in the boundary
# length, which is at most 2n + 2 edges for an n-cell polyomino and 4n + 2 for
# a polyhex.
#
# Vertex embeddings: square cell (x, y) is the unit square [x, x+1] × [y, y+1];
# hex cell (q, r) has vertex centre 3(q, r) and six corners at fixed offsets;
# iamond up-triangle (x, y) is the lower triangle of rhombus (x/3, y/3) and a
# down-triangle the upper one. All three follow the Heesch challenge verifier,
# which validated the hex and iamond walkers against Kaplan's exhaustive
# tables.

+ BoundaryWord
  -> .direction_count(grid)
    grid.id == "O" ? 4 : 6

  # The boundary word of a hole-free polyform.
  -> .of(shape)
    raise "boundary words are defined for hole-free shapes" if !shape.hole_free?
    return BoundaryWord.square(shape.cells) if shape.grid.id == "O"
    return BoundaryWord.hexagonal(shape.cells) if shape.grid.id == "H"
    BoundaryWord.iamond(shape.cells)

  -> .vertex_key(v)
    "[v[0]],[v[1]]"

  # Follow directed boundary edges from the least vertex, preferring the
  # sharpest right turn at pinch vertices so the interior stays on the left.
  # `edges` maps vertex key -> [vertex, [letters]]; `vectors` are the travel
  # vectors per letter; `preference` lists the turn deltas to try in order.
  -> .walk(edges, vectors, preference, total)
    n = vectors.size
    start = nil
    keys = edges.keys
    i = 0
    while i < keys.size
      v = edges[keys[i]][0]
      start = v if start == nil || v[0] < start[0] || (v[0] == start[0] && v[1] < start[1])
      i += 1
    raise "empty boundary" if start == nil
    remaining = {}
    i = 0
    while i < keys.size
      remaining[keys[i]] = edges[keys[i]][1].dup
      i += 1
    d = remaining[BoundaryWord.vertex_key(start)].min
    word = []
    cur = start
    steps = 0
    while steps < total
      ck = BoundaryWord.vertex_key(cur)
      remaining[ck] = remaining[ck].select ->(x) x != d
      word.push(d)
      cur = [cur[0] + vectors[d][0], cur[1] + vectors[d][1]]
      steps += 1
      break if cur[0] == start[0] && cur[1] == start[1] && BoundaryWord.all_used?(remaining)
      cands = remaining.fetch(BoundaryWord.vertex_key(cur), nil)
      raise "boundary walk dead-ends at [BoundaryWord.vertex_key(cur)]: the shape is not a single hole-free region" if cands == nil || cands.size == 0
      chosen = 0 - 1
      t = 0
      while t < preference.size && chosen < 0
        nd = (d + preference[t]) % n
        chosen = nd if cands.include?(nd)
        t += 1
      raise "no continuation at [BoundaryWord.vertex_key(cur)]" if chosen < 0
      d = chosen
    raise "outer boundary is not a single cycle" if word.size != total
    word

  -> .all_used?(remaining)
    keys = remaining.keys
    i = 0
    while i < keys.size
      return false if remaining[keys[i]].size > 0
      i += 1
    true

  -> .add_edge(edges, v, letter)
    k = BoundaryWord.vertex_key(v)
    edges[k] = [v, []] if !edges.key?(k)
    edges[k][1].push(letter)
    nil

  # Square grid: letters 0 = +x, 1 = +y, 2 = -x, 3 = -y.
  -> .square(cells)
    present = TilingGrid.index(cells)
    edges = {}
    total = 0
    i = 0
    while i < cells.size
      x = cells[i][0]
      y = cells[i][1]
      i += 1
      if !present.key?(TilingGrid.cell_key([x, y - 1]))
        BoundaryWord.add_edge(edges, [x, y], 0)
        total += 1
      if !present.key?(TilingGrid.cell_key([x + 1, y]))
        BoundaryWord.add_edge(edges, [x + 1, y], 1)
        total += 1
      if !present.key?(TilingGrid.cell_key([x, y + 1]))
        BoundaryWord.add_edge(edges, [x + 1, y + 1], 2)
        total += 1
      if !present.key?(TilingGrid.cell_key([x - 1, y]))
        BoundaryWord.add_edge(edges, [x, y + 1], 3)
        total += 1
    BoundaryWord.walk(edges, [[1, 0], [0, 1], [-1, 0], [0, -1]], [3, 0, 1], total)

  -> .hex_corners
    [[1, 1], [-1, 2], [-2, 1], [-1, -1], [1, -2], [2, -1]]

  # Hexagonal grid: cell (q, r) has vertex centre 3(q, r); the six corners
  # are listed counterclockwise and letter i is the travel corner[i] ->
  # corner[i+1].
  -> .hexagonal(cells)
    corners = BoundaryWord.hex_corners
    travel = []
    i = 0
    while i < 6
      travel.push([corners[(i + 1) % 6][0] - corners[i][0], corners[(i + 1) % 6][1] - corners[i][1]])
      i += 1
    grid = TilingGrid.hexagonal
    present = TilingGrid.index(cells)
    edges = {}
    total = 0
    c = 0
    while c < cells.size
      q = cells[c][0]
      r = cells[c][1]
      c += 1
      nbs = grid.edge_neighbours([q, r])
      d = 0
      while d < nbs.size
        n = nbs[d]
        d += 1
        next if present.key?(TilingGrid.cell_key(n))
        # the corner starting the CCW traversal of the side shared with n
        i = BoundaryWord.hex_side_start(corners, n[0] - q, n[1] - r)
        BoundaryWord.add_edge(edges, [3 * q + corners[i][0], 3 * r + corners[i][1]], i)
        total += 1
    BoundaryWord.walk(edges, travel, [5, 4, 0, 1, 2, 3], total)

  # Corner index i such that corners i and i+1 are the two corners shared
  # with the neighbour at offset (dq, dr).
  -> .hex_side_start(corners, dq, dr)
    shared = []
    i = 0
    while i < 6
      j = 0
      hit = false
      while j < 6
        hit = true if corners[i][0] == 3 * dq + corners[j][0] && corners[i][1] == 3 * dr + corners[j][1]
        j += 1
      shared.push(i) if hit
      i += 1
    raise "hex side lookup failed" if shared.size != 2
    return shared[0] if (shared[0] + 1) % 6 == shared[1]
    shared[1]

  -> .tri_directions
    [[1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1], [1, -1]]

  # The three vertex-lattice corners of a triangle, counterclockwise.
  -> .tri_corners(cell)
    x = cell[0]
    y = cell[1]
    if TilingGrid.pmod(x, 3) == 0
      i = (x - TilingGrid.pmod(x, 3)) / 3
      j = (y - TilingGrid.pmod(y, 3)) / 3
      return [[i, j], [i + 1, j], [i, j + 1]]
    i = (x - 1 - TilingGrid.pmod(x - 1, 3)) / 3
    j = (y - 1 - TilingGrid.pmod(y - 1, 3)) / 3
    [[i + 1, j + 1], [i, j + 1], [i + 1, j]]

  -> .iamond(cells)
    grid = TilingGrid.iamond
    dirs = BoundaryWord.tri_directions
    present = TilingGrid.index(cells)
    edges = {}
    total = 0
    c = 0
    while c < cells.size
      cell = cells[c]
      c += 1
      corners = BoundaryWord.tri_corners(cell)
      shared = {}
      nbs = grid.edge_neighbours(cell)
      d = 0
      while d < nbs.size
        n = nbs[d]
        d += 1
        next if !present.key?(TilingGrid.cell_key(n))
        nc = BoundaryWord.tri_corners(n)
        a = 0
        while a < 3
          b = 0
          while b < 3
            if corners[a][0] == nc[b][0] && corners[a][1] == nc[b][1]
              shared[BoundaryWord.vertex_key(corners[a])] = true
            b += 1
          a += 1
      k = 0
      while k < 3
        va = corners[k]
        vb = corners[(k + 1) % 3]
        k += 1
        # an edge is interior iff both its corners are shared with one in-set
        # neighbour; two shared corners always come from the same neighbour
        # because distinct neighbours touch this triangle on distinct edges
        next if shared.key?(BoundaryWord.vertex_key(va)) && shared.key?(BoundaryWord.vertex_key(vb)) && BoundaryWord.tri_edge_shared?(cell, va, vb, nbs, present)
        step = [vb[0] - va[0], vb[1] - va[1]]
        letter = 0 - 1
        t = 0
        while t < 6
          letter = t if dirs[t][0] == step[0] && dirs[t][1] == step[1]
          t += 1
        raise "iamond edge step is not a lattice direction" if letter < 0
        BoundaryWord.add_edge(edges, va, letter)
        total += 1
    BoundaryWord.walk(edges, dirs, [5, 4, 0, 1, 2, 3], total)

  # Is the edge va-vb of `cell` shared with an in-set edge neighbour?
  -> .tri_edge_shared?(cell, va, vb, nbs, present)
    d = 0
    while d < nbs.size
      n = nbs[d]
      d += 1
      next if !present.key?(TilingGrid.cell_key(n))
      nc = BoundaryWord.tri_corners(n)
      ha = false
      hb = false
      b = 0
      while b < 3
        ha = true if nc[b][0] == va[0] && nc[b][1] == va[1]
        hb = true if nc[b][0] == vb[0] && nc[b][1] == vb[1]
        b += 1
      return true if ha && hb
    false

# The factorization criteria on a cyclic direction word: `translation?` is
# Beauquier–Nivat, `conway?` is Conway's, and `tiles?` reports which of them
# proves a shape tiles (nil when neither does — undecided).
+ TilingCriteria
  -> .opposite(d, n)
    (d + n / 2) % n

  # The run walked backwards: reversed, letters replaced by their opposites.
  -> .hat(word, from, length, n)
    out = []
    i = length - 1
    while i >= 0
      out.push(TilingCriteria.opposite(word[(from + i) % word.size], n))
      i -= 1
    out

  -> .run_equals?(word, from, other, length)
    i = 0
    while i < length
      return false if word[(from + i) % word.size] != other[i]
      i += 1
    true

  -> .palindrome?(word, from, length)
    a = 0
    b = length - 1
    m = word.size
    while a < b
      return false if word[(from + a) % m] != word[(from + b) % m]
      a += 1
      b -= 1
    true

  # Can the run of `length` letters from `from` be cut into two palindromes?
  -> .two_palindromes?(word, from, length)
    cut = 0
    while cut <= length
      return true if TilingCriteria.palindrome?(word, from, cut) && TilingCriteria.palindrome?(word, from + cut, length - cut)
      cut += 1
    false

  # Beauquier–Nivat: some rotation of the word is X Y Z X̂ Ŷ Ẑ.
  -> .translation?(word, n)
    m = word.size
    return false if m == 0 || m % 2 != 0
    half = m / 2
    rot = 0
    while rot < m
      i = 0
      while i <= half
        if TilingCriteria.run_equals?(word, rot + half, TilingCriteria.hat(word, rot, i, n), i)
          j = i
          while j <= half
            if TilingCriteria.run_equals?(word, rot + half + i, TilingCriteria.hat(word, rot + i, j - i, n), j - i)
              return true if TilingCriteria.run_equals?(word, rot + half + j, TilingCriteria.hat(word, rot + j, half - j, n), half - j)
            j += 1
        i += 1
      rot += 1
    false

  # Conway: some rotation is A B C D E F with D = Â and B, C, E, F palindromes.
  -> .conway?(word, n)
    m = word.size
    return false if m == 0
    rot = 0
    while rot < m
      la = 0
      while la <= m / 2
        a_hat = TilingCriteria.hat(word, rot, la, n)
        k = la
        while k <= m - la
          if TilingCriteria.run_equals?(word, rot + k, a_hat, la)
            if TilingCriteria.two_palindromes?(word, rot + la, k - la) && TilingCriteria.two_palindromes?(word, rot + k + la, m - k - la)
              return true
          k += 1
        la += 1
      rot += 1
    false

  # Does the shape tile the plane by one of the two criteria? `nil` when
  # neither applies — undecided, never "does not tile".
  -> .tiles?(shape)
    word = BoundaryWord.of(shape)
    n = BoundaryWord.direction_count(shape.grid)
    return :translation if TilingCriteria.translation?(word, n)
    return :conway if TilingCriteria.conway?(word, n)
    nil
