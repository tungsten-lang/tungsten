# Exact solver for ternary affine CSPs encoded as CNF.
#
# A recognized formula has one exact-one triple for each domain-three
# variable:
#
#   (x0 | x1 | x2)
#   (-x0 | -x1) (-x0 | -x2) (-x1 | -x2)
#
# and groups its remaining clauses into blocks over four distinct ternary
# variables.  A block contains exactly the 54 assignments that violate one
# affine equation over GF(3), each as a negative width-four clause.  The 27
# assignments absent from the block are therefore precisely the solutions of
#
#   a*x + b*y + c*z + d*w = rhs  (mod 3).
#
# Strict recognition turns the whole CNF into a small linear system.  Gaussian
# elimination decides it exactly; a satisfying ternary assignment is expanded
# back to a complete Boolean model and checked against the original formula by
# the caller.  Any malformed group, duplicate tuple, non-affine block, or size
# cap miss falls through to ordinary Wassat.

WASSAT_TERNARY_AFFINE_MAX_GROUPS = 512
WASSAT_TERNARY_AFFINE_MAX_EQUATIONS = 512
WASSAT_TERNARY_AFFINE_PATTERNS = 81
WASSAT_TERNARY_AFFINE_FORBIDDEN = 54

-> wassat_ternary_affine_sort4(groups, values) (i64[] i64[]) i64
  i = 1
  while i < 4
    g = groups[i]
    v = values[i]
    j = i
    while j > 0 && groups[j - 1] > g
      groups[j] = groups[j - 1]
      values[j] = values[j - 1]
      j -= 1
    groups[j] = g
    values[j] = v
    i += 1
  0

# Infer the unique affine hyperplane whose complement is `forbidden[base...]`.
# Equivalent scalar multiples are removed by requiring the first non-zero
# coefficient to be one.  Return a packed (coefficient code, rhs), plus one so
# zero remains the miss sentinel.
-> wassat_ternary_affine_infer(forbidden, base) (i8[] i64) i64
  # The competition family uses all four coordinates.  Try those 24
  # projective hyperplanes first (the leading coefficient is normalized to
  # one), then retain the complete generic search below for equations with
  # zero coefficients.  This changes only candidate order, not recognition.
  mask = 0
  while mask < 8
    c0 = 1
    c1 = (mask & 1) == 0 ? 1 : 2
    c2 = (mask & 2) == 0 ? 1 : 2
    c3 = (mask & 4) == 0 ? 1 : 2
    code = c0 + 3 * c1 + 9 * c2 + 27 * c3
    rhs = 0
    while rhs < 3
      ok = 1
      pat = 0
      while pat < WASSAT_TERNARY_AFFINE_PATTERNS && ok == 1
        q = pat
        v3 = q % 3
        q /= 3
        v2 = q % 3
        q /= 3
        v1 = q % 3
        q /= 3
        v0 = q % 3
        dot = (c0 * v0 + c1 * v1 + c2 * v2 + c3 * v3) % 3
        want = dot == rhs ? 0 : 1
        ok = 0 unless forbidden[base + pat] == want
        pat += 1
      return code * 3 + rhs + 1 if ok == 1
      rhs += 1
    mask += 1

  code = 1
  while code < WASSAT_TERNARY_AFFINE_PATTERNS
    t = code
    c0 = t % 3
    t /= 3
    c1 = t % 3
    t /= 3
    c2 = t % 3
    t /= 3
    c3 = t % 3

    first = c0
    first = c1 if first == 0
    first = c2 if first == 0
    first = c3 if first == 0
    if first == 1
      rhs = 0
      while rhs < 3
        ok = 1
        pat = 0
        while pat < WASSAT_TERNARY_AFFINE_PATTERNS && ok == 1
          q = pat
          v3 = q % 3
          q /= 3
          v2 = q % 3
          q /= 3
          v1 = q % 3
          q /= 3
          v0 = q % 3
          dot = (c0 * v0 + c1 * v1 + c2 * v2 + c3 * v3) % 3
          want = dot == rhs ? 0 : 1
          ok = 0 unless forbidden[base + pat] == want
          pat += 1
        return code * 3 + rhs + 1 if ok == 1
        rhs += 1
    code += 1
  0

# Row-echelon elimination over GF(3).  `matrix` is row-major with an augmented
# rhs column.  Free coordinates are set to zero.  Return the rank on SAT and
# -1 on an inconsistent row.
-> wassat_ternary_affine_eliminate(matrix, nrows, ncols,
                                   pivots, solution) (i8[] i64 i64 i64[] i8[]) i64
  stride = ncols + 1
  rank = 0
  col = 0
  while col < ncols && rank < nrows
    pivot = rank
    pivot += 1 while pivot < nrows && matrix[pivot * stride + col] == 0
    if pivot < nrows
      if pivot != rank
        k = col
        while k <= ncols
          a = rank * stride + k
          b = pivot * stride + k
          tmp = matrix[a]
          matrix[a] = matrix[b]
          matrix[b] = tmp
          k += 1

      # In GF(3), two is its own inverse.
      if matrix[rank * stride + col] == 2
        k = col
        while k <= ncols
          at = rank * stride + k
          x = matrix[at]
          x = 3 - x if x != 0
          matrix[at] = x
          k += 1

      r = rank + 1
      while r < nrows
        factor = matrix[r * stride + col]
        if factor != 0
          k = col
          while k <= ncols
            if factor == 1
              x = matrix[r * stride + k] - matrix[rank * stride + k]
              x += 3 if x < 0
            else
              # -2 is +1 in GF(3).
              x = matrix[r * stride + k] + matrix[rank * stride + k]
              x -= 3 if x >= 3
            matrix[r * stride + k] = x
            k += 1
        r += 1
      pivots[rank] = col
      rank += 1
    col += 1

  r = rank
  while r < nrows
    nonzero = 0
    c = 0
    while c < ncols && nonzero == 0
      nonzero = 1 if matrix[r * stride + c] != 0
      c += 1
    return -1 if nonzero == 0 && matrix[r * stride + ncols] != 0
    r += 1

  r = rank - 1
  while r >= 0
    c = pivots[r]
    value = matrix[r * stride + ncols]
    k = c + 1
    while k < ncols
      value -= matrix[r * stride + k] * solution[k]
      k += 1
    value += 3 while value < 0
    value -= 3 while value >= 3
    solution[c] = value
    r -= 1
  rank

# Return:
#   recognized=false, status=0  shape miss / bounded refusal
#   recognized=true,  status=1  SAT with a complete Boolean model
#   recognized=true,  status=-1 exact GF(3) contradiction
-> wassat_ternary_affine_solve(formula)
  miss = {
    "recognized": false, "status": 0, "model": [],
    "groups": 0, "equations": 0, "rank": 0
  }
  return miss unless formula.has_key?("flat_ncl")

  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < 12 || nv % 3 != 0
  ngroups = nv / 3
  return miss if ngroups > WASSAT_TERNARY_AFFINE_MAX_GROUPS

  # This exact header identity rejects essentially every ordinary CNF before
  # allocating recognition scratch.
  nquad = ncl - 4 * ngroups
  return miss if nquad < WASSAT_TERNARY_AFFINE_FORBIDDEN
  return miss unless nquad % WASSAT_TERNARY_AFFINE_FORBIDDEN == 0
  nequations = nquad / WASSAT_TERNARY_AFFINE_FORBIDDEN
  return miss if nequations > WASSAT_TERNARY_AFFINE_MAX_EQUATIONS

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  choices = i8[ngroups]
  amo = i8[ngroups]
  forbidden = i8[nequations * WASSAT_TERNARY_AFFINE_PATTERNS]
  fcount = i64[nequations]
  eg0 = i64[nequations]
  eg1 = i64[nequations]
  eg2 = i64[nequations]
  eg3 = i64[nequations]
  eq_index = {}
  groups = i64[4]
  values = i64[4]
  seen_equations = 0
  nchoice = 0
  namo = 0
  seen_quad = 0
  last_key = -1
  last_ei = -1

  ci = 0
  while ci < ncl
    n = lens[ci]
    off = offs[ci]
    if n == 3
      # One positive clause containing all three values of one group.
      mask = 0
      g = -1
      j = 0
      while j < 3
        l = lits[off + j]
        return miss if l <= 0 || l > nv
        gj = (l - 1) / 3
        vj = (l - 1) % 3
        g = gj if g < 0
        return miss unless gj == g
        bit = 1 << vj
        return miss if (mask & bit) != 0
        mask = mask | bit
        j += 1
      return miss unless mask == 7
      return miss if choices[g] != 0
      choices[g] = 1
      nchoice += 1
    elsif n == 2
      # The three unique negative pairs for one group.
      la = lits[off]
      lb = lits[off + 1]
      return miss if la >= 0 || lb >= 0
      a = 0 - la
      b = 0 - lb
      return miss if a > nv || b > nv || a == b
      ga = (a - 1) / 3
      gb = (b - 1) / 3
      return miss unless ga == gb
      va = (a - 1) % 3
      vb = (b - 1) % 3
      if va > vb
        tmp = va
        va = vb
        vb = tmp
      bit = 0
      bit = 1 if va == 0 && vb == 1
      bit = 2 if va == 0 && vb == 2
      bit = 4 if va == 1 && vb == 2
      return miss if bit == 0 || (amo[ga] & bit) != 0
      amo[ga] = amo[ga] | bit
      namo += 1
    elsif n == 4
      j = 0
      while j < 4
        l = lits[off + j]
        return miss if l >= 0
        v = 0 - l
        return miss if v > nv
        groups[j] = (v - 1) / 3
        values[j] = (v - 1) % 3
        j += 1
      if groups[0] > groups[1] || groups[1] > groups[2] || groups[2] > groups[3]
        wassat_ternary_affine_sort4(groups, values)
      return miss if groups[0] == groups[1] || groups[1] == groups[2] || groups[2] == groups[3]
      key = ((groups[0] * ngroups + groups[1]) * ngroups + groups[2]) * ngroups + groups[3]
      # Encoders normally emit a block's 54 forbidden tuples contiguously.
      # Cache that common case, but retain the Hash lookup for arbitrary
      # clause order and for a block that is revisited later.
      if key == last_key
        ei = last_ei
      elsif eq_index.has_key?(key)
        ei = eq_index[key]
      else
        return miss if seen_equations >= nequations
        ei = seen_equations
        eq_index[key] = ei
        eg0[ei] = groups[0]
        eg1[ei] = groups[1]
        eg2[ei] = groups[2]
        eg3[ei] = groups[3]
        seen_equations += 1
      pattern = ((values[0] * 3 + values[1]) * 3 + values[2]) * 3 + values[3]
      last_key = key
      last_ei = ei
      at = ei * WASSAT_TERNARY_AFFINE_PATTERNS + pattern
      return miss if forbidden[at] != 0
      forbidden[at] = 1
      fcount[ei] = fcount[ei] + 1
      seen_quad += 1
    else
      return miss
    ci += 1

  return miss unless nchoice == ngroups && namo == 3 * ngroups
  return miss unless seen_quad == nquad && seen_equations == nequations
  g = 0
  while g < ngroups
    return miss unless choices[g] == 1 && amo[g] == 7
    g += 1

  stride = ngroups + 1
  matrix = i8[nequations * stride]
  ei = 0
  while ei < nequations
    return miss unless fcount[ei] == WASSAT_TERNARY_AFFINE_FORBIDDEN
    packed = wassat_ternary_affine_infer(
      forbidden, ei * WASSAT_TERNARY_AFFINE_PATTERNS
    )
    return miss if packed == 0
    token = packed - 1
    rhs = token % 3
    code = token / 3
    c0 = code % 3
    code /= 3
    c1 = code % 3
    code /= 3
    c2 = code % 3
    code /= 3
    c3 = code % 3
    matrix[ei * stride + eg0[ei]] = c0
    matrix[ei * stride + eg1[ei]] = c1
    matrix[ei * stride + eg2[ei]] = c2
    matrix[ei * stride + eg3[ei]] = c3
    matrix[ei * stride + ngroups] = rhs
    ei += 1

  pivots = i64[nequations]
  solution = i8[ngroups]
  rank = wassat_ternary_affine_eliminate(
    matrix, nequations, ngroups, pivots, solution
  )
  if rank < 0
    return {
      "recognized": true, "status": -1, "model": [],
      "groups": ngroups, "equations": nequations, "rank": 0
    }

  model = []
  g = 0
  while g < ngroups
    chosen = solution[g]
    value = 0
    while value < 3
      v = g * 3 + value + 1
      model.push(value == chosen ? v : 0 - v)
      value += 1
    g += 1
  {
    "recognized": true, "status": 1, "model": model,
    "groups": ngroups, "equations": nequations, "rank": rank
  }
