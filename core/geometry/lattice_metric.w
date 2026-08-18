# Metric invariants of a lattice, from its Gram matrix.
#
# A lattice is determined up to isometry by the Gram matrix G of a basis, so
# every question below is a question about G. Writing a vector by its integer
# coordinate column x, its squared length is the quadratic form x^T G x, which
# stays an integer when G does — so minima, kissing numbers and automorphisms
# are all exact integer computations, with no distances ever taken.
#
# The quantities:
#
#   minimum          the least nonzero squared length
#   kissing number   how many vectors attain it — how many spheres touch one
#   packing radius   half the minimal distance, so spheres of that radius fit
#   determinant      det G, the square of the fundamental cell's volume
#   Voronoi cell     the points closer to the origin than to any other lattice
#                    point; its facets come from the *relevant* vectors, which
#                    are those v whose coset v + 2L contains exactly the two
#                    minima +v and -v (Voronoi's criterion)
#   automorphisms    the integer matrices U with U G U^T = G — the lattice's
#                    own symmetry group, and the notion that generalises the
#                    Bravais classification to any dimension
#
# `core/algebra/lattice_reduction.w` reduces bases; this is what a reduced
# basis is *for*.
#
# Enumeration is by brute force over a coefficient box, so the bound argument
# must be large enough to reach the vectors of interest. For the classical
# root lattices in low dimension a bound of two suffices.

+ LatticeMetric
  -> .validate(gram)
    if gram.class_name != "Array" || gram.size == 0
      raise "a Gram matrix must be a nonempty square array"
    n = gram.size
    i = 0
    while i < n
      raise "Gram matrix must be square" if gram[i].size != n
      j = 0
      while j < n
        raise "Gram matrix must be symmetric" if gram[i][j] != gram[j][i]
        j += 1
      raise "Gram matrix diagonal must be positive" if gram[i][i] <= 0
      i += 1
    n

  # Gram matrix of a basis given as integer row vectors: G = B B^T.
  -> .gram_from_basis(rows)
    n = rows.size
    out = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        total = 0
        k = 0
        while k < rows[i].size
          total += rows[i][k] * rows[j][k]
          k += 1
        row.push(total)
        j += 1
      out.push(row)
      i += 1
    out

  # Squared length of the vector with integer coordinates x.
  -> .norm2(gram, x)
    n = gram.size
    total = 0
    i = 0
    while i < n
      partial = 0
      j = 0
      while j < n
        partial += gram[i][j] * x[j]
        j += 1
      total += partial * x[i]
      i += 1
    total

  -> .inner(gram, x, y)
    n = gram.size
    total = 0
    i = 0
    while i < n
      partial = 0
      j = 0
      while j < n
        partial += gram[i][j] * y[j]
        j += 1
      total += partial * x[i]
      i += 1
    total

  # Every coefficient vector in the box [-bound, bound]^n, origin excluded.
  -> .coefficient_box(n, bound)
    vectors = [[]]
    d = 0
    while d < n
      grown = []
      i = 0
      while i < vectors.size
        v = 0 - bound
        while v <= bound
          extended = []
          k = 0
          while k < vectors[i].size
            extended.push(vectors[i][k])
            k += 1
          extended.push(v)
          grown.push(extended)
          v += 1
        i += 1
      vectors = grown
      d += 1
    out = []
    i = 0
    while i < vectors.size
      zero = true
      k = 0
      while k < n
        zero = false if vectors[i][k] != 0
        k += 1
      out.push(vectors[i]) if !zero
      i += 1
    out

  # The least nonzero squared length found within the box.
  -> .minimum(gram, bound)
    n = LatticeMetric.validate(gram)
    best = 0
    candidates = LatticeMetric.coefficient_box(n, bound)
    i = 0
    while i < candidates.size
      value = LatticeMetric.norm2(gram, candidates[i])
      best = value if best == 0 || (value > 0 && value < best)
      i += 1
    best

  -> .minimal_vectors(gram, bound)
    n = LatticeMetric.validate(gram)
    least = LatticeMetric.minimum(gram, bound)
    out = []
    candidates = LatticeMetric.coefficient_box(n, bound)
    i = 0
    while i < candidates.size
      out.push(candidates[i]) if LatticeMetric.norm2(gram, candidates[i]) == least
      i += 1
    out

  # How many lattice points sit at the minimal distance from the origin.
  -> .kissing_number(gram, bound)
    LatticeMetric.minimal_vectors(gram, bound).size

  # Spheres of this radius, centred on lattice points, touch but never overlap.
  -> .packing_radius_squared(gram, bound)
    LatticeMetric.minimum(gram, bound) * 0.25

  # det G, by Bareiss fraction-free elimination — exact in integers.
  -> .determinant(gram)
    n = LatticeMetric.validate(gram)
    m = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(gram[i][j])
        j += 1
      m.push(row)
      i += 1
    sign = 1
    previous = 1
    k = 0
    while k < n - 1
      if m[k][k] == 0
        swapped = false
        r = k + 1
        while r < n && !swapped
          if m[r][k] != 0
            tmp = m[k]
            m[k] = m[r]
            m[r] = tmp
            sign = 0 - sign
            swapped = true
          r += 1
        return 0 if !swapped
      i = k + 1
      while i < n
        j = k + 1
        while j < n
          m[i][j] = (m[i][j] * m[k][k] - m[i][k] * m[k][j]) / previous
          j += 1
        i += 1
      previous = m[k][k]
      k += 1
    sign * m[n - 1][n - 1]

  # A lattice is unimodular when its fundamental cell has volume one.
  -> .unimodular?(gram)
    LatticeMetric.determinant(gram) == 1

  # Even lattices have all squared lengths even, which forces the diagonal.
  -> .even?(gram)
    n = LatticeMetric.validate(gram)
    ok = true
    i = 0
    while i < n
      ok = false if gram[i][i] % 2 != 0
      i += 1
    ok

  # Voronoi's criterion: v is relevant exactly when the coset v + 2L has
  # precisely two minimal vectors, namely v and -v. The relevant vectors are
  # the facet normals of the Voronoi cell, so counting them counts the facets.
  -> .relevant_vectors(gram, bound)
    n = LatticeMetric.validate(gram)
    out = []
    cosets = LatticeMetric.coefficient_box(n, 1)
    c = 0
    while c < cosets.size
      coset = cosets[c]
      c += 1
      skip = false
      k = 0
      while k < n
        skip = true if coset[k] < 0
        k += 1
      next if skip
      # Minimal vectors of the coset coset + 2L.
      best = 0 - 1
      winners = []
      shifts = LatticeMetric.coefficient_box(n, bound)
      shifts.push(LatticeMetric.zero_vector(n))
      s = 0
      while s < shifts.size
        candidate = []
        k = 0
        while k < n
          candidate.push(coset[k] + 2 * shifts[s][k])
          k += 1
        s += 1
        value = LatticeMetric.norm2(gram, candidate)
        next if value == 0
        if best < 0 || value < best
          best = value
          winners = [candidate]
        elsif value == best
          winners.push(candidate)
      out.push(winners[0]) if winners.size == 2
    out

  -> .zero_vector(n)
    out = []
    i = 0
    while i < n
      out.push(0)
      i += 1
    out

  # Facets of the Voronoi cell: every relevant vector and its negative.
  -> .voronoi_facet_count(gram, bound)
    LatticeMetric.relevant_vectors(gram, bound).size * 2

  # Order of the automorphism group: integer matrices U with U G U^T = G.
  # Each basis vector must map to a lattice vector of the same length whose
  # inner products with the earlier images match the Gram matrix, which makes
  # the search a short backtrack. This is the Bravais group of the lattice,
  # and it is defined in every dimension.
  -> .automorphism_group_order(gram, bound)
    n = LatticeMetric.validate(gram)
    pool = LatticeMetric.coefficient_box(n, bound)
    LatticeMetric.extend_automorphism(gram, pool, [], n)

  -> .extend_automorphism(gram, pool, chosen, n)
    return 1 if chosen.size == n
    index = chosen.size
    total = 0
    i = 0
    while i < pool.size
      candidate = pool[i]
      i += 1
      next if LatticeMetric.norm2(gram, candidate) != gram[index][index]
      ok = true
      j = 0
      while j < chosen.size
        ok = false if LatticeMetric.inner(gram, chosen[j], candidate) != gram[j][index]
        j += 1
      next if !ok
      extended = []
      k = 0
      while k < chosen.size
        extended.push(chosen[k])
        k += 1
      extended.push(candidate)
      total += LatticeMetric.extend_automorphism(gram, pool, extended, n)
    total

  # ---- classical lattices ---------------------------------------------

  -> .z(n)
    rows = []
    i = 0
    while i < n
      row = []
      j = 0
      while j < n
        row.push(i == j ? 1 : 0)
        j += 1
      rows.push(row)
      i += 1
    LatticeMetric.gram_from_basis(rows)

  # A_n = { x in Z^(n+1) : sum x = 0 }, basis e_i - e_(i+1).
  -> .a(n)
    rows = []
    i = 0
    while i < n
      row = []
      j = 0
      while j <= n
        value = 0
        value = 1 if j == i
        value = 0 - 1 if j == i + 1
        row.push(value)
        j += 1
      rows.push(row)
      i += 1
    LatticeMetric.gram_from_basis(rows)

  # The hexagonal lattice is A2.
  -> .hexagonal
    LatticeMetric.a(2)

  # D_n = { x in Z^n : sum x even }, basis e_i - e_(i+1) and e_(n-1) + e_n.
  -> .d(n)
    raise "D_n needs n at least 2" if n < 2
    rows = []
    i = 0
    while i < n - 1
      row = []
      j = 0
      while j < n
        value = 0
        value = 1 if j == i
        value = 0 - 1 if j == i + 1
        row.push(value)
        j += 1
      rows.push(row)
      i += 1
    last = []
    j = 0
    while j < n
      value = 0
      value = 1 if j == n - 2 || j == n - 1
      last.push(value)
      j += 1
    rows.push(last)
    LatticeMetric.gram_from_basis(rows)

  # E8 by its Cartan matrix: even, unimodular, and the densest lattice
  # packing in eight dimensions. Its 240 minimal vectors are the E8 roots.
  -> .e8
    edges = [[0, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [1, 3]]
    gram = []
    i = 0
    while i < 8
      row = []
      j = 0
      while j < 8
        row.push(i == j ? 2 : 0)
        j += 1
      gram.push(row)
      i += 1
    e = 0
    while e < edges.size
      a = edges[e][0]
      b = edges[e][1]
      gram[a][b] = 0 - 1
      gram[b][a] = 0 - 1
      e += 1
    gram
