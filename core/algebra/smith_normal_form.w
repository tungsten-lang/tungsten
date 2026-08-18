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

  # The invariant factors d1 | d2 | ... | dr, as a positive-integer array.
  # Its length is the rank; a zero matrix yields an empty array.
  -> .invariant_factors(matrix)
    width = SmithNormalForm.validate(matrix)
    m = SmithNormalForm.copy(matrix)
    height = m.size
    factors = []
    t = 0
    while t < height && t < width
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
      break if pi < 0
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
      # Clear the pivot row and column, repeating while remainders appear.
      cleared = false
      while !cleared
        cleared = true
        i = t + 1
        while i < height
          if m[i][t] != 0
            q = m[i][t] / m[t][t]
            j = t
            while j < width
              m[i][j] = m[i][j] - q * m[t][j]
              j += 1
            if m[i][t] != 0
              swap = m[t]
              m[t] = m[i]
              m[i] = swap
              cleared = false
          i += 1
        j = t + 1
        while j < width
          if m[t][j] != 0
            q = m[t][j] / m[t][t]
            i = t
            while i < height
              m[i][j] = m[i][j] - q * m[i][t]
              i += 1
            if m[t][j] != 0
              i = 0
              while i < height
                v = m[i][t]
                m[i][t] = m[i][j]
                m[i][j] = v
                i += 1
              cleared = false
          j += 1
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
