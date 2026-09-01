# Smith normal form of an integer matrix.
#
# Every integer matrix A factors as U A V = D with U, V unimodular and D
# diagonal, where the diagonal entries d1 | d2 | ... | dr divide one another in
# turn. Those `invariant factors` are unique, and they classify the situation
# completely: the cokernel of A as a map of lattices is
#
#   Z^m / A Z^n  =  Z/d1 (+) Z/d2 (+) ... (+) Z/dr (+) Z^(m-r)
#
# so the same computation answers "what is the quotient of this lattice", "what
# abelian group is this presentation", and "what is the rank" at once.
#
# The reduction is integer Gaussian elimination. Pick the nonzero entry of
# smallest magnitude as pivot, clear its row and column by subtracting integer
# multiples (a remainder that survives is strictly smaller, so the process
# terminates), then enforce the divisibility chain: if some later entry is not
# a multiple of the pivot, fold its row into the pivot row and reduce again.

+ SmithNormalForm
  -> .integer?(value)
    name = value.class_name
    name == "Integer" || name == "Int" || name == "BigInt"

  -> .abs(value)
    value < 0 ? 0 - value : value

  # Integer division rounding toward zero is what we want here: the remainder
  # keeps the sign of the dividend but is strictly smaller in magnitude.
  -> .copy(matrix)
    out = []
    i = 0
    while i < matrix.size
      row = []
      j = 0
      while j < matrix[i].size
        row.push(matrix[i][j])
        j += 1
      out.push(row)
      i += 1
    out

  -> .validate(matrix)
    if matrix.class_name != "Array" || matrix.size == 0
      raise "Smith normal form needs a nonempty matrix"
    width = matrix[0].size
    raise "matrix rows must be nonempty" if width == 0
    i = 0
    while i < matrix.size
      raise "matrix must be rectangular" if matrix[i].class_name != "Array" || matrix[i].size != width
      j = 0
      while j < width
        raise "matrix entries must be integers" if !SmithNormalForm.integer?(matrix[i][j])
        j += 1
      i += 1
    width

  # Quotient rounded to NEAREST (ties toward zero), so the remainder magnitude
  # is at most half the divisor's. Truncating division leaves remainders up to
  # the full divisor, and in the elimination below that difference is the line
  # between polynomial-sized intermediates and the classic exponential entry
  # blowup (measured: a 7x7 matrix of entries in [-20, 20] did not finish in
  # 10 minutes with truncation; milliseconds with nearest).
  -> .nearest_quotient(a, b)
    q = a / b
    r = a - q * b
    if SmithNormalForm.abs(r) * 2 > SmithNormalForm.abs(b)
      if (r < 0) == (b < 0)
        q += 1
      else
        q -= 1
    q

  # Balanced residue of v mod d (in [-d/2, d/2]); identity when d is nil.
  # Fast-exits on entries already in range — the reduction sweep visits the
  # whole trailing block every pass, and most entries are already small.
  -> .balanced_mod(v, d)
    return v if d == nil
    if v >= 0
      return v if v + v <= d
    else
      return v if 0 - (v + v) <= d
    r = v % d
    r += d if r < 0
    r -= d if r + r > d
    r

  # The invariant factors d1 | d2 | ... | dr, as a positive-integer array.
  # Its length is the rank; a zero matrix yields an empty array.
  #
  # A mod-determinant lane exists (invariant_factors_mod_det below): every
  # determinantal divisor D_k divides D = |det|, entry adjustments by
  # multiples of D change every k-minor by a multiple of D, so
  # gcd(D_k(adjusted), D) = D_k(original), and the true factors recover
  # from the mod-D pivot products. It is verified factor-exact against
  # this path (12/12 randomized n = 24..32), but it is NOT routed
  # automatically: measured 2x slower at n = 48..64, and the n >= 96 wall
  # turns out to be elimination PASS COUNT, not coefficient growth —
  # bounded entries do not rescue it. Large-n SNF needs an HNF-first
  # algorithm; until then this exact elimination is the best lane.
  # Square matrices at n >= 40 route through the HNF-first mod-D lane
  # (measured crossover ~40; n=64 5.8x faster, n=96 in ~8 s where the
  # exact elimination never finishes, n=128 in ~110 s). Singular inputs
  # fall back inside the lane.
  -> .invariant_factors(matrix)
    width = SmithNormalForm.validate(matrix)
    if matrix.size == width && matrix.size >= 40
      return SmithNormalForm.invariant_factors_hnf(matrix)
    SmithNormalForm.pivot_diagonal(matrix, nil)

  # Mod-determinant invariant factors (square, nonsingular; see the note
  # above). Falls back to the exact lane when det = 0.
  -> .invariant_factors_mod_det(matrix)
    width = SmithNormalForm.validate(matrix)
    height = matrix.size
    if height == width
      d = ExactIntegerLinearAlgebra.modular_determinant(matrix)
      d = 0 - d if d < 0
      if d != 0
        return SmithNormalForm.factors_from_pivots(
          SmithNormalForm.pivot_diagonal(matrix, d), d)
    SmithNormalForm.pivot_diagonal(matrix, nil)

  # Iterative extended Euclid: [g, x, y] with x*a + y*b = g, g >= 0.
  -> .xgcd(a, b)
    old_r = a
    r = b
    old_x = 1
    x = 0
    old_y = 0
    y = 1
    while r != 0
      q = old_r / r
      t = old_r - q * r
      old_r = r
      r = t
      t = old_x - q * x
      old_x = x
      x = t
      t = old_y - q * y
      old_y = y
      y = t
    return [0 - old_r, 0 - old_x, 0 - old_y] if old_r < 0
    [old_r, old_x, old_y]

  # One triangularization sweep: extended-gcd row combines zero every
  # below-diagonal entry column by column — each entry dies in ONE
  # unimodular 2x2 combine ([x y; -v u], det = (xa + yb)/g = 1), so there
  # is no restart pathology. Entries stay balanced mod d throughout (a
  # multiple-of-d adjustment, legitimate under the pivot-product recovery).
  -> .hnf_pass(m, n, d)
    t = 0
    while t < n
      i = t + 1
      while i < n
        b = m[i][t]
        if b != 0
          a = m[t][t]
          if a == 0
            tmp = m[t]
            m[t] = m[i]
            m[i] = tmp
          else
            e = SmithNormalForm.xgcd(a, b)
            g = e[0]
            bez_x = e[1]
            bez_y = e[2]
            u = a / g
            v = b / g
            j = t
            while j < n
              rt = m[t][j]
              ri = m[i][j]
              m[t][j] = SmithNormalForm.balanced_mod(bez_x * rt + bez_y * ri, d)
              m[i][j] = SmithNormalForm.balanced_mod(u * ri - v * rt, d)
              j += 1
        i += 1
      # HNF normalization: reduce row t right of the pivot to nearest
      # residues via column operations (below-diagonal entries of column t
      # are zero, so only rows 0..t change). Without this the alternating
      # sweep stalls — the transposed pass keeps receiving the same
      # unreduced mass and the ping-pong never converges past small n.
      p = m[t][t]
      if p != 0
        j = t + 1
        while j < n
          q = SmithNormalForm.nearest_quotient(m[t][j], p)
          if q != 0
            i = 0
            while i <= t
              m[i][j] = SmithNormalForm.balanced_mod(m[i][j] - q * m[i][t], d)
              i += 1
          j += 1
      t += 1

  -> .transpose_in_place(m, n)
    i = 0
    while i < n
      j = i + 1
      while j < n
        t = m[i][j]
        m[i][j] = m[j][i]
        m[j][i] = t
        j += 1
      i += 1

  -> .diagonal?(m, n)
    i = 0
    while i < n
      j = 0
      while j < n
        return false if i != j && m[i][j] != 0
        j += 1
      i += 1
    true

  # HNF ping-pong invariant factors for a square NONSINGULAR matrix:
  # alternate triangularization sweeps with transposes until diagonal (each
  # sweep kills the below-diagonal mass; the transpose flips what the
  # combines spread above), then recover the true factors from the pivot
  # products — factors_from_pivots is correct for ANY diagonalization of a
  # mod-D-congruent matrix, so convergence speed affects time, never
  # correctness. Falls back to the exact elimination when d = 0 or the
  # round cap trips.
  -> .invariant_factors_hnf(matrix)
    width = SmithNormalForm.validate(matrix)
    height = matrix.size
    return SmithNormalForm.pivot_diagonal(matrix, nil) if height != width
    d = ExactIntegerLinearAlgebra.modular_determinant(matrix)
    d = 0 - d if d < 0
    return SmithNormalForm.pivot_diagonal(matrix, nil) if d == 0
    m = SmithNormalForm.copy(matrix)
    n = height
    rounds = 0
    done = false
    while rounds < 100 && !done
      SmithNormalForm.hnf_pass(m, n, d)
      SmithNormalForm.transpose_in_place(m, n)
      done = SmithNormalForm.diagonal?(m, n)
      rounds += 1
      ccall("w_probe_counter_add", 4, 1)
    return SmithNormalForm.pivot_diagonal(matrix, nil) if !done
    pivots = []
    i = 0
    while i < n
      p = m[i][i]
      p = 0 - p if p < 0
      p = d if p == 0
      pivots.push(p)
      i += 1
    # The recovery needs prod(first k pivots) = D_k, which holds only for a
    # DIVISIBILITY-CHAIN diagonal. The ping-pong's diagonal is unordered, so
    # first apply the classical pairwise (a, b) -> (gcd, a*b/gcd) sweeps —
    # they preserve the diagonal's SNF and terminate in a chain.
    changed = true
    while changed
      changed = false
      i = 0
      while i < n - 1
        j = i + 1
        while j < n
          a = pivots[i]
          b = pivots[j]
          g = a.gcd(b)
          if g != a
            pivots[i] = g
            pivots[j] = (a / g) * b
            changed = true
          j += 1
        i += 1
    SmithNormalForm.factors_from_pivots(pivots, d)

  # Recover the invariant factors from the mod-D pivot diagonal.
  -> .factors_from_pivots(pivots, d)
    factors = []
    r = 1
    previous = 1
    i = 0
    while i < pivots.size
      r = (r * pivots[i]) % d
      g = r.gcd(d)
      g = d if g == 0
      factors.push(g / previous)
      previous = g
      i += 1
    factors

  # The elimination core: returns the |pivot| diagonal. With a modulus the
  # trailing block is reduced into balanced residues after every clearing
  # pass (each adjustment is a multiple-of-modulus entry change — see the
  # invariant_factors doc for why that preserves what we recover); without
  # one this is the exact algorithm and the diagonal IS the factor list.
  -> .pivot_diagonal(matrix, modulus)
    width = SmithNormalForm.validate(matrix)
    m = SmithNormalForm.copy(matrix)
    height = m.size
    factors = []
    t = 0
    while t < height && t < width
      # Clear the pivot row and column, re-selecting the least-magnitude pivot
      # from the whole remaining block on every pass: after a surviving
      # remainder the smallest entry may live anywhere, and pivoting on it is
      # what keeps the euclidean cascade's quotients (and so entry growth)
      # small.
      cleared = false
      empty = false
      while !cleared
        if modulus != nil
          i = t
          while i < height
            j = t
            while j < width
              m[i][j] = SmithNormalForm.balanced_mod(m[i][j], modulus)
              j += 1
            i += 1
        # Locate the nonzero entry of least magnitude in the remaining block.
        pi = 0 - 1
        pj = 0 - 1
        best = 0
        i = t
        while i < height
          j = t
          while j < width
            v = SmithNormalForm.abs(m[i][j])
            if v != 0 && (pi < 0 || v < best)
              best = v
              pi = i
              pj = j
            j += 1
          i += 1
        if pi < 0
          empty = true
          break
        # Move the pivot to (t, t).
        swap = m[t]
        m[t] = m[pi]
        m[pi] = swap
        i = 0
        while i < height
          v = m[i][t]
          m[i][t] = m[i][pj]
          m[i][pj] = v
          i += 1
        cleared = true
        i = t + 1
        while i < height
          if m[i][t] != 0
            q = SmithNormalForm.nearest_quotient(m[i][t], m[t][t])
            j = t
            while j < width
              m[i][j] = m[i][j] - q * m[t][j]
              j += 1
            cleared = false if m[i][t] != 0
          i += 1
        j = t + 1
        while j < width
          if m[t][j] != 0
            q = SmithNormalForm.nearest_quotient(m[t][j], m[t][t])
            i = t
            while i < height
              m[i][j] = m[i][j] - q * m[i][t]
              i += 1
            cleared = false if m[t][j] != 0
          j += 1
      if empty
        if modulus != nil
          while t < height && t < width
            factors.push(modulus)
            t += 1
        break
      # Enforce divisibility: every remaining entry must be a multiple of the
      # pivot, or the chain d1 | d2 | ... would fail.
      pivot = m[t][t]
      violated = false
      i = t + 1
      while i < height && !violated
        j = t + 1
        while j < width && !violated
          if m[i][j] % pivot != 0
            violated = true
            k = t
            while k < width
              m[t][k] = m[t][k] + m[i][k]
              k += 1
          j += 1
        i += 1
      next if violated
      value = SmithNormalForm.abs(m[t][t])
      factors.push(value)
      t += 1
    factors

  -> .rank(matrix)
    SmithNormalForm.invariant_factors(matrix).size

  # Torsion part of the cokernel: the invariant factors greater than 1.
  -> .torsion(matrix)
    out = []
    SmithNormalForm.invariant_factors(matrix).each ->(d)
      out.push(d) if d > 1
    out

  # A square matrix is unimodular exactly when every invariant factor is 1 and
  # it has full rank — equivalently, it is a change of lattice basis.
  -> .unimodular?(matrix)
    factors = SmithNormalForm.invariant_factors(matrix)
    return false if factors.size != matrix.size || factors.size != matrix[0].size
    ok = true
    factors.each ->(d)
      ok = false if d != 1
    ok

  # Index of the sublattice spanned by the rows, i.e. the order of the torsion
  # quotient; 0 when the rows do not span a finite-index sublattice.
  -> .lattice_index(matrix)
    factors = SmithNormalForm.invariant_factors(matrix)
    return 0 if factors.size < matrix[0].size
    product = 1
    factors.each ->(d)
      product = product * d
    product

  # --- Helpers shared by the transform-tracking decomposition -------------

  -> .identity(size)
    out = []
    i = 0
    while i < size
      row = []
      j = 0
      while j < size
        row.push(i == j ? 1 : 0)
        j += 1
      out.push(row)
      i += 1
    out

  # Rectangular integer product: (h x k) * (k x w).
  -> .multiply(left, right)
    out = []
    i = 0
    while i < left.size
      row = []
      j = 0
      while j < right[0].size
        total = 0
        k = 0
        while k < right.size
          total += left[i][k] * right[k][j]
          k += 1
        row.push(total)
        j += 1
      out.push(row)
      i += 1
    out

  -> .apply(matrix, vector)
    out = []
    i = 0
    while i < matrix.size
      total = 0
      j = 0
      while j < vector.size
        total += matrix[i][j] * vector[j]
        j += 1
      out.push(total)
      i += 1
    out

  -> .transpose(matrix)
    out = []
    j = 0
    while j < matrix[0].size
      row = []
      i = 0
      while i < matrix.size
        row.push(matrix[i][j])
        i += 1
      out.push(row)
      j += 1
    out

  -> .column(matrix, index)
    out = []
    i = 0
    while i < matrix.size
      out.push(matrix[i][index])
      i += 1
    out

  -> .same_matrix?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i].size != right[i].size
      j = 0
      while j < left[i].size
        return false if left[i][j] != right[i][j]
        j += 1
      i += 1
    true

  -> .same_vector?(left, right)
    return false if left.size != right.size
    i = 0
    while i < left.size
      return false if left[i] != right[i]
      i += 1
    true

  # Horizontal concatenation [A | B] — the shape that presents a sum of
  # images, e.g. the coinvariants of a group action, (A1 - I | A2 - I).
  -> .augment(left, right)
    raise "augment needs matrices of equal height" if left.size != right.size
    out = []
    i = 0
    while i < left.size
      row = []
      left[i].each ->(x)
        row.push(x)
      right[i].each ->(x)
        row.push(x)
      out.push(row)
      i += 1
    out

  -> .subtract_identity(matrix)
    out = SmithNormalForm.copy(matrix)
    i = 0
    while i < out.size
      out[i][i] = out[i][i] - 1
      i += 1
    out

  # Elementary operations, applied to the work matrix and mirrored on the
  # transforms. A row operation is E * A: it multiplies U on the left and
  # U^-1 on the right by E^-1, which is a column operation there. A column
  # operation is A * E: V picks up E on the right, V^-1 picks up E^-1 on the
  # left, a row operation.

  -> .swap_rows(a, u, u_inverse, x, y)
    return nil if x == y
    row = a[x]
    a[x] = a[y]
    a[y] = row
    row = u[x]
    u[x] = u[y]
    u[y] = row
    u_inverse.each ->(r)
      value = r[x]
      r[x] = r[y]
      r[y] = value
    nil

  -> .swap_columns(a, v, v_inverse, x, y)
    return nil if x == y
    a.each ->(r)
      value = r[x]
      r[x] = r[y]
      r[y] = value
    v.each ->(r)
      value = r[x]
      r[x] = r[y]
      r[y] = value
    row = v_inverse[x]
    v_inverse[x] = v_inverse[y]
    v_inverse[y] = row
    nil

  # row_i -= q * row_t; on U^-1: column_t += q * column_i.
  -> .subtract_row(a, u, u_inverse, i, t, q)
    return nil if q == 0
    j = 0
    while j < a[i].size
      a[i][j] = a[i][j] - q * a[t][j]
      j += 1
    j = 0
    while j < u[i].size
      u[i][j] = u[i][j] - q * u[t][j]
      j += 1
    u_inverse.each ->(r)
      r[t] = r[t] + q * r[i]
    nil

  # column_j -= q * column_t; on V^-1: row_t += q * row_j.
  -> .subtract_column(a, v, v_inverse, j, t, q)
    return nil if q == 0
    a.each ->(r)
      r[j] = r[j] - q * r[t]
    v.each ->(r)
      r[j] = r[j] - q * r[t]
    k = 0
    while k < v_inverse[t].size
      v_inverse[t][k] = v_inverse[t][k] + q * v_inverse[j][k]
      k += 1
    nil

  # row_t += row_i; on U^-1: column_i -= column_t.
  -> .add_row(a, u, u_inverse, t, i)
    j = 0
    while j < a[t].size
      a[t][j] = a[t][j] + a[i][j]
      j += 1
    j = 0
    while j < u[t].size
      u[t][j] = u[t][j] + u[i][j]
      j += 1
    u_inverse.each ->(r)
      r[i] = r[i] - r[t]
    nil

  -> .negate_row(a, u, u_inverse, t)
    j = 0
    while j < a[t].size
      a[t][j] = 0 - a[t][j]
      j += 1
    j = 0
    while j < u[t].size
      u[t][j] = 0 - u[t][j]
      j += 1
    u_inverse.each ->(r)
      r[t] = 0 - r[t]
    nil

  # --- Decomposition with transforms --------------------------------------

  # The full factorisation U A V = D, with U, V unimodular and their inverses
  # carried along. Same elimination as `invariant_factors`, mirrored on the
  # transforms, so the two are independent implementations of the same
  # diagonal — the certificate cross-checks them.
  #
  # What the transforms buy: the last columns of V are a basis of ker A; the
  # columns of U^-1 are generators of the cokernel Z^m / A Z^n, the i-th of
  # order d_i (or infinite past the rank); the last rows of U are the integer
  # functionals that vanish on the image and detect the free part.
  -> .decompose(matrix)
    width = SmithNormalForm.validate(matrix)
    a = SmithNormalForm.copy(matrix)
    height = a.size
    u = SmithNormalForm.identity(height)
    u_inverse = SmithNormalForm.identity(height)
    v = SmithNormalForm.identity(width)
    v_inverse = SmithNormalForm.identity(width)
    t = 0
    while t < height && t < width
      pi = 0 - 1
      pj = 0 - 1
      best = 0
      i = t
      while i < height
        j = t
        while j < width
          value = SmithNormalForm.abs(a[i][j])
          if value != 0 && (pi < 0 || value < best)
            best = value
            pi = i
            pj = j
          j += 1
        i += 1
      break if pi < 0
      SmithNormalForm.swap_rows(a, u, u_inverse, t, pi)
      SmithNormalForm.swap_columns(a, v, v_inverse, t, pj)
      cleared = false
      while !cleared
        cleared = true
        i = t + 1
        while i < height
          if a[i][t] != 0
            q = a[i][t] / a[t][t]
            SmithNormalForm.subtract_row(a, u, u_inverse, i, t, q)
            if a[i][t] != 0
              SmithNormalForm.swap_rows(a, u, u_inverse, t, i)
              cleared = false
          i += 1
        j = t + 1
        while j < width
          if a[t][j] != 0
            q = a[t][j] / a[t][t]
            SmithNormalForm.subtract_column(a, v, v_inverse, j, t, q)
            if a[t][j] != 0
              SmithNormalForm.swap_columns(a, v, v_inverse, t, j)
              cleared = false
          j += 1
        if cleared
          pivot = a[t][t]
          i = t + 1
          while i < height && cleared
            j = t + 1
            while j < width && cleared
              if a[i][j] % pivot != 0
                SmithNormalForm.add_row(a, u, u_inverse, t, i)
                cleared = false
              j += 1
            i += 1
      SmithNormalForm.negate_row(a, u, u_inverse, t) if a[t][t] < 0
      t += 1
    SmithDecomposition.new(matrix, a, u, u_inverse, v, v_inverse)

  # Basis of the integer kernel {x : A x = 0}, as a list of vectors.
  -> .kernel(matrix)
    SmithNormalForm.decompose(matrix).kernel

  # The cokernel Z^m / A Z^n as an abstract group.
  -> .cokernel(matrix)
    SmithNormalForm.decompose(matrix).cokernel

# A finitely generated abelian group in invariant-factor form:
# Z^free_rank (+) Z/d1 (+) ... (+) Z/dk with 1 < d1 | d2 | ... | dk.
# This is what a Smith normal form classifies, so it is the answer type of
# cokernels, abelianisations and homology groups alike.
+ FinitelyGeneratedAbelianGroup
  -> new(free_rank, torsion)
    @free_rank = free_rank
    @torsion = []
    torsion.each ->(d)
      raise "torsion orders must exceed 1" if d < 2
      @torsion.push(d)

  -> .trivial
    FinitelyGeneratedAbelianGroup.new(0, [])

  -> .free(rank)
    FinitelyGeneratedAbelianGroup.new(rank, [])

  -> .cyclic(order)
    return FinitelyGeneratedAbelianGroup.free(1) if order == 0
    order = 0 - order if order < 0
    return FinitelyGeneratedAbelianGroup.trivial if order == 1
    FinitelyGeneratedAbelianGroup.new(0, [order])

  # The group presented by a relation matrix whose columns are relations
  # among the standard generators of Z^rows: the cokernel of the matrix.
  -> .from_relations(matrix)
    factors = SmithNormalForm.invariant_factors(matrix)
    torsion = []
    factors.each ->(d)
      torsion.push(d) if d > 1
    FinitelyGeneratedAbelianGroup.new(matrix.size - factors.size, torsion)

  -> free_rank
    @free_rank

  -> torsion
    @torsion

  -> rank
    @free_rank

  -> finite?
    @free_rank == 0

  -> trivial?
    @free_rank == 0 && @torsion.size == 0

  -> torsion_free?
    @torsion.size == 0

  -> cyclic?
    @free_rank + @torsion.size <= 1

  # Number of elements, 0 when infinite.
  -> order
    return 0 if @free_rank > 0
    product = 1
    @torsion.each ->(d)
      product = product * d
    product

  -> torsion_order
    product = 1
    @torsion.each ->(d)
      product = product * d
    product

  -> ==(other)
    return false if other.class_name != "FinitelyGeneratedAbelianGroup"
    return false if other.free_rank != @free_rank
    SmithNormalForm.same_vector?(other.torsion, @torsion)

  -> eql?(other)
    self == other

  -> to_s
    return "0" if trivial?
    parts = []
    if @free_rank == 1
      parts.push("Z")
    if @free_rank > 1
      parts.push("Z^" + @free_rank.to_s)
    @torsion.each ->(d)
      parts.push("Z/" + d.to_s)
    text = parts[0]
    i = 1
    while i < parts.size
      text = text + " (+) " + parts[i]
      i += 1
    text

  -> inspect
    to_s

# U A V = D, with everything an integer matrix and U, V unimodular.
+ SmithDecomposition
  -> new(@matrix, @diagonal, @left, @left_inverse, @right, @right_inverse)
    @rows = @diagonal.size
    @cols = @diagonal[0].size
    @rank = 0
    while @rank < @rows && @rank < @cols && @diagonal[@rank][@rank] != 0
      @rank += 1
    @certificate = nil

  -> matrix
    @matrix

  -> diagonal
    @diagonal

  -> left
    @left

  -> right
    @right

  -> left_inverse
    @left_inverse

  -> right_inverse
    @right_inverse

  -> rows
    @rows

  -> cols
    @cols

  -> rank
    @rank

  -> invariant_factors
    out = []
    i = 0
    while i < @rank
      out.push(@diagonal[i][i])
      i += 1
    out

  -> torsion
    out = []
    invariant_factors.each ->(d)
      out.push(d) if d > 1
    out

  # Index of the image A Z^n inside its saturation (the product of the
  # invariant factors), 1 when the image is a direct summand.
  -> image_index
    product = 1
    invariant_factors.each ->(d)
      product = product * d
    product

  -> image_saturated?
    image_index == 1

  # --- kernel ---

  -> kernel_rank
    @cols - @rank

  # Basis of {x in Z^n : A x = 0}: the columns of V past the rank. They
  # span a saturated sublattice because V is unimodular.
  -> kernel
    out = []
    j = @rank
    while j < @cols
      out.push(SmithNormalForm.column(@right, j))
      j += 1
    out

  # V^-1 x has zeros in the first `rank` places exactly when A x = 0; the
  # remaining entries are the coordinates of x in the kernel basis.
  -> in_kernel?(vector)
    y = SmithNormalForm.apply(@right_inverse, vector)
    i = 0
    while i < @rank
      return false if y[i] != 0
      i += 1
    true

  -> kernel_coordinates(vector)
    y = SmithNormalForm.apply(@right_inverse, vector)
    i = 0
    while i < @rank
      raise "vector is not in the kernel" if y[i] != 0
      i += 1
    out = []
    while i < @cols
      out.push(y[i])
      i += 1
    out

  # --- cokernel ---

  -> cokernel_free_rank
    @rows - @rank

  -> cokernel
    FinitelyGeneratedAbelianGroup.new(cokernel_free_rank, torsion)

  # Generators of Z^m / A Z^n, torsion ones first (orders in
  # `cokernel_orders`), then the free ones: the columns of U^-1 for the
  # indices whose invariant factor is not 1.
  -> cokernel_generators
    out = []
    i = 0
    while i < @rows
      if i >= @rank || @diagonal[i][i] > 1
        out.push(SmithNormalForm.column(@left_inverse, i))
      i += 1
    out

  # Orders of the generators above, 0 for infinite.
  -> cokernel_orders
    out = []
    i = 0
    while i < @rows
      if i >= @rank
        out.push(0)
      else
        out.push(@diagonal[i][i]) if @diagonal[i][i] > 1
      i += 1
    out

  # Coordinates of the class of a vector in Z^m / A Z^n with respect to
  # `cokernel_generators`: U x, reduced modulo the orders. The class is zero
  # exactly when the vector lies in the image.
  -> cokernel_class(vector)
    y = SmithNormalForm.apply(@left, vector)
    out = []
    i = 0
    while i < @rows
      if i >= @rank
        out.push(y[i])
      else
        d = @diagonal[i][i]
        if d > 1
          r = y[i] % d
          r += d if r < 0
          out.push(r)
      i += 1
    out

  -> in_image?(vector)
    y = SmithNormalForm.apply(@left, vector)
    i = 0
    while i < @rows
      if i >= @rank
        return false if y[i] != 0
      else
        return false if y[i] % @diagonal[i][i] != 0
      i += 1
    true

  # Integer functionals vanishing on the image and detecting the free part
  # of the cokernel: the last rows of U. Their common kernel is the
  # saturation of the image.
  -> cokernel_functionals
    out = []
    i = @rank
    while i < @rows
      out.push(@left[i])
      i += 1
    out

  -> certificate
    @certificate = SmithDecompositionCertificate.new(self) if @certificate == nil
    @certificate

  -> certified?
    certificate.verified?

  -> to_s
    text = "SmithDecomposition(" + @rows.to_s + "x" + @cols.to_s
    text = text + ", factors " + invariant_factors.to_s
    text + ", kernel rank " + kernel_rank.to_s + ")"

  -> inspect
    to_s

# Replays U A V and the inverse products, checks the diagonal shape and the
# divisibility chain, and cross-checks the factors against the independent
# `invariant_factors` elimination.
+ SmithDecompositionCertificate
  -> new(@decomposition)
    @verified_cache = nil

  -> decomposition
    @decomposition

  -> proof_kind
    :smith_normal_form_replay

  -> kernel_checked?
    true

  -> verified?
    return @verified_cache if @verified_cache != nil
    answer = false
    begin
      answer = verify!
    rescue error
      answer = false
    @verified_cache = answer
    answer

  -> verify!
    return false if @decomposition.class_name != "SmithDecomposition"
    a = @decomposition.matrix
    d = @decomposition.diagonal
    u = @decomposition.left
    v = @decomposition.right
    rows = @decomposition.rows
    cols = @decomposition.cols
    return false if a.size != rows || a[0].size != cols
    product = SmithNormalForm.multiply(SmithNormalForm.multiply(u, a), v)
    return false if !SmithNormalForm.same_matrix?(product, d)
    identity_rows = SmithNormalForm.identity(rows)
    identity_cols = SmithNormalForm.identity(cols)
    return false if !SmithNormalForm.same_matrix?(
      SmithNormalForm.multiply(u, @decomposition.left_inverse), identity_rows)
    return false if !SmithNormalForm.same_matrix?(
      SmithNormalForm.multiply(v, @decomposition.right_inverse), identity_cols)
    rank = @decomposition.rank
    i = 0
    while i < rows
      j = 0
      while j < cols
        if i != j
          return false if d[i][j] != 0
        else
          return false if i < rank && d[i][i] <= 0
          return false if i >= rank && d[i][i] != 0
        j += 1
      i += 1
    i = 1
    while i < rank
      return false if d[i][i] % d[i - 1][i - 1] != 0
      i += 1
    SmithNormalForm.same_vector?(
      @decomposition.invariant_factors, SmithNormalForm.invariant_factors(a))

  -> certified?
    verified?

  -> to_s
    "SmithDecompositionCertificate(" + @decomposition.to_s + ")"

  -> inspect
    to_s
