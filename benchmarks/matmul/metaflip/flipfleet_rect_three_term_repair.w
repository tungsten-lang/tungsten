# Exact rank-at-most-three recognition for sparse rectangular GF(2) carriers.
#
# For a carrier C, let d be the rank of its U-flattening (the dimension of
# the VxW slice space).  Tensor rank at most three forces d <= 3:
#
#   d=1: factor the single VxW matrix at matrix rank <=3.
#   d=2: either two of the three U factors coincide (a 2+1 matrix-rank
#        split), or the U factors are alpha,beta,alpha^beta and there is a
#        rank-one Z with A+Z and B+Z rank one.
#   d=3: an ordered GL(3,2) basis of the seven nonzero slice combinations
#        consists of three rank-one matrices.
#
# The implementation enumerates those cases completely.  It is used by the
# offline <2,2,5> correlated three-term repair experiment; callers still gate
# every materialized full scheme independently.

use flipfleet_rect_two_term_repair

-> ffr3tr_matrix_xor(left, right, out, rows) (i64[] i64[] i64[] i64) i64
  row = 0 ## i64
  while row < rows
    out[row] = left[row] ^ right[row]
    row += 1
  rows

-> ffr3tr_matrix_outer(v, w, out, rows) (i64 i64 i64[] i64) i64
  row = 0 ## i64
  while row < rows
    if ((v >> row) & 1) != 0
      out[row] = w
    else
      out[row] = 0
    row += 1
  rows

# Decompose a VxW matrix of rank zero through three.  Rows are W-bit masks;
# the returned V masks are the coordinate columns in a row-space basis.
# A return below zero means matrix rank exceeds three.
-> ffr3tr_matrix_rank_three(rows, vwidth, out_v, out_w) (i64[] i64 i64[] i64[]) i64
  basis = i64[3]
  rank = 0 ## i64
  row = 0 ## i64
  while row < vwidth
    value = rows[row] ## i64
    code = 0 ## i64
    if value != 0
      candidate = 1 ## i64
      limit = 1 << rank ## i64
      while candidate < limit && code == 0
        combined = 0 ## i64
        bit = 0 ## i64
        while bit < rank
          if ((candidate >> bit) & 1) != 0
            combined = combined ^ basis[bit]
          bit += 1
        if combined == value
          code = candidate
        candidate += 1
      if code == 0
        if rank >= 3
          return 0 - 1
        basis[rank] = value
        code = 1 << rank
        rank += 1
    bit = 0
    while bit < rank
      if ((code >> bit) & 1) != 0
        out_v[bit] = out_v[bit] | (1 << row)
      bit += 1
    row += 1
  bit = 0
  while bit < rank
    out_w[bit] = basis[bit]
    bit += 1
  rank

-> ffr3tr_matrix_combo(basis, rows, code, out) (i64[] i64 i64 i64[]) i64
  row = 0 ## i64
  while row < rows
    value = 0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((code >> bit) & 1) != 0
        value = value ^ basis[bit * rows + row]
      bit += 1
    out[row] = value
    row += 1
  rows

-> ffr3tr_matrix_is_combo(value, basis, rows, code) (i64[] i64[] i64 i64) i64
  row = 0 ## i64
  while row < rows
    combined = 0 ## i64
    bit = 0 ## i64
    while bit < 3
      if ((code >> bit) & 1) != 0
        combined = combined ^ basis[bit * rows + row]
      bit += 1
    if value[row] != combined
      return 0
    row += 1
  1

# Extract up to three independent U slices.  basis contains three flattened
# VxW matrices and coeff[a] is the three-bit coordinate code of U slice a.
# Return four as soon as a fourth independent slice proves tensor rank >3.
-> ffr3tr_slice_space(carrier, n, m, p, basis, coeff) (i64[] i64 i64 i64 i64[] i64[]) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  rank = 0 ## i64
  a = 0 ## i64
  while a < uwidth
    slice = i64[vwidth]
    nonzero = 0 ## i64
    b = 0 ## i64
    while b < vwidth
      row = 0 ## i64
      c = 0 ## i64
      while c < wwidth
        cell = (a * vwidth + b) * wwidth + c ## i64
        if ffrrw_bit(carrier, cell) != 0
          row = row | (1 << c)
        c += 1
      slice[b] = row
      nonzero = nonzero | row
      b += 1
    code = 0 ## i64
    if nonzero != 0
      candidate = 1 ## i64
      limit = 1 << rank ## i64
      while candidate < limit && code == 0
        if ffr3tr_matrix_is_combo(slice, basis, vwidth, candidate) == 1
          code = candidate
        candidate += 1
      if code == 0
        if rank >= 3
          return 4
        b = 0
        while b < vwidth
          basis[rank * vwidth + b] = slice[b]
          b += 1
        code = 1 << rank
        rank += 1
    coeff[a] = code
    a += 1
  rank

# The chosen matrix basis is expressed by `codes` in the original slice
# basis.  Solve the tiny change of basis directly and return its U masks.
-> ffr3tr_transform_u(coeff, uwidth, codes, dimension, out_u) (i64[] i64 i64[] i64 i64[]) i64
  a = 0 ## i64
  while a < uwidth
    wanted = coeff[a] ## i64
    found = 0 ## i64
    lambda = 0 ## i64
    limit = 1 << dimension ## i64
    while lambda < limit && found == 0
      combined = 0 ## i64
      bit = 0 ## i64
      while bit < dimension
        if ((lambda >> bit) & 1) != 0
          combined = combined ^ codes[bit]
        bit += 1
      if combined == wanted
        found = 1
        bit = 0
        while bit < dimension
          if ((lambda >> bit) & 1) != 0
            out_u[bit] = out_u[bit] | (1 << a)
          bit += 1
      lambda += 1
    if found == 0
      return 0
    a += 1
  1

-> ffr3tr_try_weight3_z(a, b, ua, ub, zv, zw, vwidth, out_u, out_v, out_w) (i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  z = i64[vwidth]
  az = i64[vwidth]
  bz = i64[vwidth]
  zf = i64[2]
  af = i64[2]
  bf = i64[2]
  x = ffr3tr_matrix_outer(zv, zw, z, vwidth) ## i64
  x = ffr3tr_matrix_xor(a, z, az, vwidth)
  x = ffr3tr_matrix_xor(b, z, bz, vwidth)
  if ffr2tr_matrix_rank_one(az, vwidth, af) != 1 || ffr2tr_matrix_rank_one(bz, vwidth, bf) != 1
    return 0
  if ua == 0 || ub == 0 || (ua ^ ub) == 0
    return 0
  out_u[0] = ua
  out_v[0] = af[0]
  out_w[0] = af[1]
  out_u[1] = ub
  out_v[1] = bf[0]
  out_w[1] = bf[1]
  out_u[2] = ua ^ ub
  out_v[2] = zv
  out_w[2] = zw
  1

# Complete weight-three U-relation case for a two-dimensional slice space.
# A = X+Z and B = Y+Z.  If either input has matrix rank two, all useful Z lie
# among the nine nonzero column-space/row-space outer products.  If both have
# rank one, enumerate the exact shared-left/shared-right neighbourhood (2,044
# candidates for 10x10 matrices).  meta[0]=tested Z, meta[1]=anchor rank.
-> ffr3tr_d2_weight3(a, b, ua, ub, vwidth, wwidth, out_u, out_v, out_w, meta) (i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  av = i64[2]
  aw = i64[2]
  bv = i64[2]
  bw = i64[2]
  ra = ffr2tr_matrix_rank_two(a, vwidth, av, aw) ## i64
  rb = ffr2tr_matrix_rank_two(b, vwidth, bv, bw) ## i64
  meta[0] = 0
  meta[1] = 0
  if ra < 1 || rb < 1 || ra > 2 || rb > 2
    return 0

  anchor_v = av
  anchor_w = aw
  anchor_rank = ra ## i64
  if rb == 2
    anchor_v = bv
    anchor_w = bw
    anchor_rank = rb
  meta[1] = anchor_rank
  if anchor_rank == 2
    lefts = i64[3]
    rights = i64[3]
    lefts[0] = anchor_v[0]
    lefts[1] = anchor_v[1]
    lefts[2] = anchor_v[0] ^ anchor_v[1]
    rights[0] = anchor_w[0]
    rights[1] = anchor_w[1]
    rights[2] = anchor_w[0] ^ anchor_w[1]
    li = 0 ## i64
    while li < 3
      ri = 0 ## i64
      while ri < 3
        meta[0] += 1
        if ffr3tr_try_weight3_z(a, b, ua, ub, lefts[li], rights[ri], vwidth, out_u, out_v, out_w) == 1
          return 3
        ri += 1
      li += 1
    return 0

  # When both matrices are rank one, A=a*b and B=c*d.  The cross outer
  # product Z=a*d gives A+Z=a*(b+d) and B+Z=(a+c)*d, both rank at most one.
  # (The symmetric Z=c*b is a second exact choice.)  The previous exhaustive
  # scan over every nonzero factor mask was therefore unnecessary and, worse,
  # failed closed above width 20.  These two algebraic candidates are complete
  # for arbitrary widths that fit the i64 factor representation.
  if ra == 1 && rb == 1
    meta[0] += 1
    if ffr3tr_try_weight3_z(a, b, ua, ub, av[0], bw[0], vwidth, out_u, out_v, out_w) == 1
      return 3
    meta[0] += 1
    if ffr3tr_try_weight3_z(a, b, ua, ub, bv[0], aw[0], vwidth, out_u, out_v, out_w) == 1
      return 3
  0

# meta: U-flatten rank, case (10 / 20..22 / 29 / 30), returned rank,
# tested GL/basis choices, tested weight-three Z, weight-three anchor rank.
-> ffr3tr_decompose(carrier, n, m, p, out_u, out_v, out_w, meta) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  if uwidth < 1 || vwidth < 1 || wwidth < 1 || uwidth > 62 || vwidth > 62 || wwidth > 62
    return 0 - 1
  i = 0 ## i64
  while i < meta.size()
    meta[i] = 0
    i += 1
  basis = i64[3 * vwidth]
  coeff = i64[uwidth]
  dimension = ffr3tr_slice_space(carrier, n, m, p, basis, coeff) ## i64
  meta[0] = dimension
  if dimension == 0
    return 0
  if dimension > 3
    return 0 - 1

  if dimension == 1
    matrix = i64[vwidth]
    x = ffr3tr_matrix_combo(basis, vwidth, 1, matrix) ## i64
    mv = i64[3]
    mw = i64[3]
    rank = ffr3tr_matrix_rank_three(matrix, vwidth, mv, mw) ## i64
    meta[1] = 10
    meta[2] = rank
    if rank < 1 || rank > 3
      return 0 - 1
    umask = 0 ## i64
    a = 0 ## i64
    while a < uwidth
      if coeff[a] != 0
        umask = umask | (1 << a)
      a += 1
    term = 0 ## i64
    while term < rank
      out_u[term] = umask
      out_v[term] = mv[term]
      out_w[term] = mw[term]
      term += 1
    return rank

  if dimension == 2
    left_codes = i64[3]
    right_codes = i64[3]
    left_codes[0] = 1
    right_codes[0] = 2
    left_codes[1] = 1
    right_codes[1] = 3
    left_codes[2] = 2
    right_codes[2] = 3
    best_rank = 4 ## i64
    best_variant = 0 ## i64
    best_u = i64[3]
    best_v = i64[3]
    best_w = i64[3]
    variant = 0 ## i64
    while variant < 3
      meta[3] += 1
      left = i64[vwidth]
      right = i64[vwidth]
      x = ffr3tr_matrix_combo(basis, vwidth, left_codes[variant], left) ## i64
      x = ffr3tr_matrix_combo(basis, vwidth, right_codes[variant], right)
      lv = i64[3]
      lw = i64[3]
      rv = i64[3]
      right_w_factors = i64[3]
      lr = ffr3tr_matrix_rank_three(left, vwidth, lv, lw) ## i64
      rr = ffr3tr_matrix_rank_three(right, vwidth, rv, right_w_factors) ## i64
      if lr > 0 && rr > 0 && lr + rr <= 3 && lr + rr < best_rank
        codes = i64[2]
        codes[0] = left_codes[variant]
        codes[1] = right_codes[variant]
        transformed = i64[2]
        if ffr3tr_transform_u(coeff, uwidth, codes, 2, transformed) == 1
          at = 0 ## i64
          term = 0 ## i64
          while term < lr
            best_u[at] = transformed[0]
            best_v[at] = lv[term]
            best_w[at] = lw[term]
            at += 1
            term += 1
          term = 0
          while term < rr
            best_u[at] = transformed[1]
            best_v[at] = rv[term]
            right_w_value = right_w_factors[term] ## i64
            best_w[at] = right_w_value
            at += 1
            term += 1
          best_rank = at
          best_variant = variant
      variant += 1
    if best_rank <= 3
      term = 0
      while term < best_rank
        out_u[term] = best_u[term]
        out_v[term] = best_v[term]
        out_w[term] = best_w[term]
        term += 1
      meta[1] = 20 + best_variant
      meta[2] = best_rank
      return best_rank

    a_matrix = i64[vwidth]
    b_matrix = i64[vwidth]
    x = ffr3tr_matrix_combo(basis, vwidth, 1, a_matrix)
    x = ffr3tr_matrix_combo(basis, vwidth, 2, b_matrix)
    codes = i64[2]
    codes[0] = 1
    codes[1] = 2
    transformed = i64[2]
    if ffr3tr_transform_u(coeff, uwidth, codes, 2, transformed) != 1
      return 0 - 1
    zmeta = i64[2]
    rank = ffr3tr_d2_weight3(a_matrix, b_matrix, transformed[0], transformed[1], vwidth, wwidth, out_u, out_v, out_w, zmeta) ## i64
    meta[4] = zmeta[0]
    meta[5] = zmeta[1]
    if rank == 3
      meta[1] = 29
      meta[2] = 3
      return 3
    return 0 - 1

  # dimension == 3.  Factor the seven nonzero combinations once, then
  # enumerate ordered independent triples.  These are the 168 elements of
  # GL(3,2); the first all-rank-one basis is a decomposition.
  rank_one = i64[8]
  combo_v = i64[8]
  combo_w = i64[8]
  code = 1 ## i64
  while code < 8
    matrix = i64[vwidth]
    factor = i64[2]
    x = ffr3tr_matrix_combo(basis, vwidth, code, matrix) ## i64
    if ffr2tr_matrix_rank_one(matrix, vwidth, factor) == 1
      rank_one[code] = 1
      combo_v[code] = factor[0]
      combo_w[code] = factor[1]
    code += 1
  code0 = 1 ## i64
  while code0 < 8
    code1 = 1 ## i64
    while code1 < 8
      if code1 != code0
        code2 = 1 ## i64
        while code2 < 8
          if code2 != code0 && code2 != code1 && code2 != (code0 ^ code1)
            meta[3] += 1
            if rank_one[code0] == 1 && rank_one[code1] == 1 && rank_one[code2] == 1
              codes = i64[3]
              codes[0] = code0
              codes[1] = code1
              codes[2] = code2
              transformed = i64[3]
              if ffr3tr_transform_u(coeff, uwidth, codes, 3, transformed) == 1
                out_u[0] = transformed[0]
                out_v[0] = combo_v[code0]
                out_w[0] = combo_w[code0]
                out_u[1] = transformed[1]
                out_v[1] = combo_v[code1]
                out_w[1] = combo_w[code1]
                out_u[2] = transformed[2]
                out_v[2] = combo_v[code2]
                out_w[2] = combo_w[code2]
                meta[1] = 30
                meta[2] = 3
                return 3
          code2 += 1
      code1 += 1
    code0 += 1
  meta[2] = 4
  0 - 1

-> ffr3tr_rebuild(out_u, out_v, out_w, rank, n, m, p, carrier) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  words = ffrrw_tensor_words(n, m, p) ## i64
  rebuilt = i64[words]
  z = ffrrw_build_term_target(out_u, out_v, out_w, rank, n, m, p, rebuilt) ## i64
  ffrrw_equal(rebuilt, carrier, words)
