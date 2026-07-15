# Correlated two-term repair for sparse rectangular GF(2) residuals.
#
# Given a rank-(R-1) near-scheme S with exact residual G = T xor S, replacing
# terms x_i,x_j by y_1,y_2 is exact precisely when
#
#   y_1 + y_2 = G + x_i + x_j.
#
# The right side is a small explicit tensor.  This module recognizes tensor
# rank at most two without SAT: its U-flattening has rank at most two, and over
# GF(2) there are only three nonzero bases in a two-dimensional slice space.
# Each basis choice is accepted only when both VxW matrices are rank one.  A
# rank-one U flattening reduces to an ordinary matrix-rank-at-most-two test.
# Every materialized repair is still independently reconstructed in the
# caller before admission.

use flipfleet_rect_residual_worm

-> ffr2tr_matrix_equal(left, right, rows) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rows
    if left[i] != right[i]
      return 0
    i += 1
  1

-> ffr2tr_matrix_xor_equal(value, left, right, rows) (i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rows
    if value[i] != (left[i] ^ right[i])
      return 0
    i += 1
  1

-> ffr2tr_matrix_copy(source, target, rows) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < rows
    target[i] = source[i]
    i += 1
  rows

# Factor a nonzero VxW matrix of rank one.  Rows are W-bit masks.
# out[0]=V factor, out[1]=W factor.
-> ffr2tr_matrix_rank_one(rows, vwidth, out) (i64[] i64 i64[]) i64
  v = 0 ## i64
  w = 0 ## i64
  r = 0 ## i64
  while r < vwidth
    row = rows[r] ## i64
    if row != 0
      if w == 0
        w = row
      elsif row != w
        return 0
      v = v | (1 << r)
    r += 1
  if v == 0 || w == 0
    return 0
  out[0] = v
  out[1] = w
  1

# Decompose a VxW matrix of rank one or two into rank-one matrices.  The row
# space is enough: every row must be 0, q1, q2, or q1 xor q2.
-> ffr2tr_matrix_rank_two(rows, vwidth, out_v, out_w) (i64[] i64 i64[] i64[]) i64
  q1 = 0 ## i64
  q2 = 0 ## i64
  v1 = 0 ## i64
  v2 = 0 ## i64
  r = 0 ## i64
  while r < vwidth
    row = rows[r] ## i64
    code = 0 ## i64
    if row != 0
      if q1 == 0
        q1 = row
        code = 1
      elsif row == q1
        code = 1
      elsif q2 == 0
        q2 = row
        code = 2
      elsif row == q2
        code = 2
      elsif row == (q1 ^ q2)
        code = 3
      else
        return 0 - 1
    if (code & 1) != 0
      v1 = v1 | (1 << r)
    if (code & 2) != 0
      v2 = v2 | (1 << r)
    r += 1
  if q1 == 0
    return 0
  out_v[0] = v1
  out_w[0] = q1
  if q2 == 0
    return 1
  out_v[1] = v2
  out_w[1] = q2
  2

# Materialize a rank-at-most-two tensor carrier.  All current FlipFleet shapes
# have factor widths <=62; the guard keeps shifts in signed i64 territory.
# meta[0]=U-flattening rank, meta[1]=basis variant (0..2, or 10 for rank-one
# U flattening), meta[2]=returned tensor rank.
-> ffr2tr_decompose(carrier, n, m, p, out_u, out_v, out_w, meta) (i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  uwidth = n * m ## i64
  vwidth = m * p ## i64
  wwidth = n * p ## i64
  if uwidth < 1 || vwidth < 1 || wwidth < 1 || uwidth > 62 || vwidth > 62 || wwidth > 62
    return 0 - 1
  slices = i64[uwidth * vwidth]
  a = 0 ## i64
  while a < uwidth
    b = 0 ## i64
    while b < vwidth
      row = 0 ## i64
      c = 0 ## i64
      while c < wwidth
        bit = (a * vwidth + b) * wwidth + c ## i64
        if ffrrw_bit(carrier, bit) != 0
          row = row | (1 << c)
        c += 1
      slices[a * vwidth + b] = row
      b += 1
    a += 1

  basis_a = i64[vwidth]
  basis_b = i64[vwidth]
  coeff = i64[uwidth]
  have_a = 0 ## i64
  have_b = 0 ## i64
  a = 0
  while a < uwidth
    slice = i64[vwidth]
    b = 0
    nonzero = 0 ## i64
    while b < vwidth
      slice[b] = slices[a * vwidth + b]
      nonzero = nonzero | slice[b]
      b += 1
    code = 0 ## i64
    if nonzero != 0
      if have_a == 0
        z = ffr2tr_matrix_copy(slice, basis_a, vwidth) ## i64
        have_a = 1
        code = 1
      elsif ffr2tr_matrix_equal(slice, basis_a, vwidth) == 1
        code = 1
      elsif have_b == 0
        z = ffr2tr_matrix_copy(slice, basis_b, vwidth)
        have_b = 1
        code = 2
      elsif ffr2tr_matrix_equal(slice, basis_b, vwidth) == 1
        code = 2
      elsif ffr2tr_matrix_xor_equal(slice, basis_a, basis_b, vwidth) == 1
        code = 3
      else
        meta[0] = 3
        return 0 - 1
    coeff[a] = code
    a += 1
  if have_a == 0
    meta[0] = 0
    meta[2] = 0
    return 0

  if have_b == 0
    matrix_v = i64[2]
    matrix_w = i64[2]
    rank = ffr2tr_matrix_rank_two(basis_a, vwidth, matrix_v, matrix_w) ## i64
    meta[0] = 1
    meta[1] = 10
    meta[2] = rank
    if rank < 1 || rank > 2
      return 0 - 1
    umask = 0 ## i64
    a = 0
    while a < uwidth
      if coeff[a] == 1
        umask = umask | (1 << a)
      a += 1
    i = 0 ## i64
    while i < rank
      out_u[i] = umask
      out_v[i] = matrix_v[i]
      out_w[i] = matrix_w[i]
      i += 1
    return rank

  meta[0] = 2
  combo = i64[vwidth]
  variant = 0 ## i64
  while variant < 3
    left = basis_a
    right = basis_b
    if variant > 0
      b = 0
      while b < vwidth
        combo[b] = basis_a[b] ^ basis_b[b]
        b += 1
    if variant == 1
      right = combo
    if variant == 2
      left = basis_b
      right = combo
    left_factor = i64[2]
    right_factor = i64[2]
    if ffr2tr_matrix_rank_one(left, vwidth, left_factor) == 1 && ffr2tr_matrix_rank_one(right, vwidth, right_factor) == 1
      ul = 0 ## i64
      ur = 0 ## i64
      a = 0
      while a < uwidth
        alpha = coeff[a] & 1 ## i64
        beta = (coeff[a] >> 1) & 1 ## i64
        lc = alpha ## i64
        rc = beta ## i64
        if variant == 1
          lc = alpha ^ beta
          rc = beta
        if variant == 2
          lc = alpha ^ beta
          rc = alpha
        if lc != 0
          ul = ul | (1 << a)
        if rc != 0
          ur = ur | (1 << a)
        a += 1
      if ul != 0 && ur != 0
        out_u[0] = ul
        out_v[0] = left_factor[0]
        out_w[0] = left_factor[1]
        out_u[1] = ur
        out_v[1] = right_factor[0]
        out_w[1] = right_factor[1]
        meta[1] = variant
        meta[2] = 2
        return 2
    variant += 1
  meta[2] = 3
  0 - 1

-> ffr2tr_rebuild(out_u, out_v, out_w, rank, n, m, p, carrier) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  words = ffrrw_tensor_words(n, m, p) ## i64
  rebuilt = i64[words]
  z = ffrrw_build_term_target(out_u, out_v, out_w, rank, n, m, p, rebuilt) ## i64
  ffrrw_equal(rebuilt, carrier, words)
