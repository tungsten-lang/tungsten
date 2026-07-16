# Symmetry-canonical basin identities for pure-Tungsten Metaflip.
#
# The exact tensor gate remains authoritative.  These 62-bit digests are used
# only to avoid mistaking a D3/reversal image for a new basin and to attach
# lineage/telemetry to equivalent states.  The orbit is the six valid tensor
# axis automorphisms (C3 rotations plus reflection) times simultaneous index
# reversal.  A matrix-rank histogram adds a cheap invariant under arbitrary
# GL changes on the three index spaces.

use ../scheme
use ../strategies/escape

-> ffbi_reverse_factor(mask, n) (i64 i64) i64
  result = 0 ## i64
  row = 0 ## i64
  while row < n
    col = 0 ## i64
    while col < n
      source = row * n + col ## i64
      if ((mask >> source) & 1) == 1
        target = (n - 1 - row) * n + (n - 1 - col) ## i64
        result = result | (1 << target)
      col += 1
    row += 1
  result

# One component of a D3 image.  Keeping this scalar is important in the live
# coordinator: identities are recomputed on every changed island, while the
# campaign-lifetime allocator does not collect a temporary 3-word array.
# code 0..2 is C3^code; code 3..5 applies the tensor reflection first.
-> ffbi_transform_factor(u, v, w, n, code, reverse, axis) (i64 i64 i64 i64 i64 i64 i64) i64
  result = u ## i64
  if code == 0
    if axis == 1
      result = v
    if axis == 2
      result = w
  if code == 1
    result = v
    if axis == 1
      result = ffe_transpose(w, n)
    if axis == 2
      result = ffe_transpose(u, n)
  if code == 2
    result = ffe_transpose(w, n)
    if axis == 1
      result = u
    if axis == 2
      result = ffe_transpose(v, n)
  if code == 3
    result = ffe_transpose(v, n)
    if axis == 1
      result = ffe_transpose(u, n)
    if axis == 2
      result = ffe_transpose(w, n)
  if code == 4
    result = ffe_transpose(u, n)
    if axis == 1
      result = w
    if axis == 2
      result = v
  if code == 5
    result = w
    if axis == 1
      result = ffe_transpose(v, n)
    if axis == 2
      result = u
  if reverse != 0
    result = ffbi_reverse_factor(result, n)
  result

-> ffbi_transform_term(u, v, w, n, code, reverse, output) (i64 i64 i64 i64 i64 i64 i64[]) i64
  output[0] = ffbi_transform_factor(u, v, w, n, code, reverse, 0)
  output[1] = ffbi_transform_factor(u, v, w, n, code, reverse, 1)
  output[2] = ffbi_transform_factor(u, v, w, n, code, reverse, 2)
  1

-> ffbi_matrix_rank(mask, n) (i64 i64) i64
  # Seven 8-bit row slots fit in one i64. Gaussian elimination can therefore
  # stay scalar instead of leaking one tiny array per factor-rank query.
  rows = 0 ## i64
  row_mask = (1 << n) - 1 ## i64
  r = 0 ## i64
  while r < n
    rows = rows | (((mask >> (r * n)) & row_mask) << (r * 8))
    r += 1
  rank = 0 ## i64
  col = 0 ## i64
  while col < n
    pivot = rank ## i64
    while pivot < n && ((((rows >> (pivot * 8)) & 255) >> col) & 1) == 0
      pivot += 1
    if pivot < n
      if pivot != rank
        pivot_row = (rows >> (pivot * 8)) & 255 ## i64
        rank_row = (rows >> (rank * 8)) & 255 ## i64
        rows = rows ^ (pivot_row << (pivot * 8)) ^ (rank_row << (pivot * 8))
        rows = rows ^ (rank_row << (rank * 8)) ^ (pivot_row << (rank * 8))
      basis = (rows >> (rank * 8)) & 255 ## i64
      r = 0
      while r < n
        row = (rows >> (r * 8)) & 255 ## i64
        if r != rank && ((row >> col) & 1) == 1
          changed = row ^ basis ## i64
          rows = rows ^ (row << (r * 8)) ^ (changed << (r * 8))
        r += 1
      rank += 1
    col += 1
  rank

-> ffbi_view_rank(state, current) (i64[] i64) i64
  if current != 0
    return ffw_current_rank(state)
  ffw_best_rank(state)

-> ffbi_view_u(state, index, current) (i64[] i64 i64) i64
  if current != 0
    return ffw_read_current_u(state, index)
  ffw_read_best_u(state, index)

-> ffbi_view_v(state, index, current) (i64[] i64 i64) i64
  if current != 0
    return ffw_read_current_v(state, index)
  ffw_read_best_v(state, index)

-> ffbi_view_w(state, index, current) (i64[] i64 i64) i64
  if current != 0
    return ffw_read_current_w(state, index)
  ffw_read_best_w(state, index)

# Histograms of GF(2) matrix ranks are unchanged by left/right invertible
# basis changes.  Sort the three axis digests so D3-equivalent states agree.
-> ffbi_gl_invariant_view(state, current) (i64[] i64) i64
  n = ffw_n(state) ## i64
  rank = ffbi_view_rank(state, current) ## i64
  digest0 = 0 ## i64
  digest1 = 0 ## i64
  digest2 = 0 ## i64
  axis = 0 ## i64
  while axis < 3
    h0 = 0 ## i64
    h1 = 0 ## i64
    h2 = 0 ## i64
    h3 = 0 ## i64
    h4 = 0 ## i64
    h5 = 0 ## i64
    h6 = 0 ## i64
    h7 = 0 ## i64
    i = 0 ## i64
    while i < rank
      factor = ffbi_view_u(state, i, current) ## i64
      if axis == 1
        factor = ffbi_view_v(state, i, current)
      if axis == 2
        factor = ffbi_view_w(state, i, current)
      matrix_rank = ffbi_matrix_rank(factor, n) ## i64
      if matrix_rank == 0
        h0 += 1
      if matrix_rank == 1
        h1 += 1
      if matrix_rank == 2
        h2 += 1
      if matrix_rank == 3
        h3 += 1
      if matrix_rank == 4
        h4 += 1
      if matrix_rank == 5
        h5 += 1
      if matrix_rank == 6
        h6 += 1
      if matrix_rank == 7
        h7 += 1
      i += 1
    digest = 17 ## i64
    digest = (digest * 1009 + h0) % 2147483647
    if n >= 1
      digest = (digest * 1009 + h1 * 2) % 2147483647
    if n >= 2
      digest = (digest * 1009 + h2 * 3) % 2147483647
    if n >= 3
      digest = (digest * 1009 + h3 * 4) % 2147483647
    if n >= 4
      digest = (digest * 1009 + h4 * 5) % 2147483647
    if n >= 5
      digest = (digest * 1009 + h5 * 6) % 2147483647
    if n >= 6
      digest = (digest * 1009 + h6 * 7) % 2147483647
    if n >= 7
      digest = (digest * 1009 + h7 * 8) % 2147483647
    if axis == 0
      digest0 = digest
    if axis == 1
      digest1 = digest
    if axis == 2
      digest2 = digest
    axis += 1
  if digest0 > digest1
    swap = digest0 ## i64
    digest0 = digest1
    digest1 = swap
  if digest1 > digest2
    swap = digest1
    digest1 = digest2
    digest2 = swap
  if digest0 > digest1
    swap = digest0
    digest0 = digest1
    digest1 = swap
  result = 23 ## i64
  result = (result * 65537 + digest0) % 2147483647
  result = (result * 65537 + digest1) % 2147483647
  result = (result * 65537 + digest2) % 2147483647
  result

# Allocation-free C3 membership on a worker state.  This replaces export into
# three fresh capacity-sized arrays in MAP and coordinator telemetry paths.
-> ffbi_state_is_c3(state, n, current) (i64[] i64 i64) i64
  rank = ffbi_view_rank(state, current) ## i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < rank && ok == 1
    ru = ffbi_view_v(state, i, current) ## i64
    rv = ffe_transpose(ffbi_view_w(state, i, current), n) ## i64
    rotated_w = ffe_transpose(ffbi_view_u(state, i, current), n) ## i64
    found = 0 ## i64
    j = 0 ## i64
    while j < rank && found == 0
      if ffbi_view_u(state, j, current) == ru && ffbi_view_v(state, j, current) == rv && ffbi_view_w(state, j, current) == rotated_w
        found = 1
      j += 1
    if found == 0
      ok = 0
    i += 1
  ok

-> ffbi_term_hash(u, v, w, which) (i64 i64 i64 i64) i64
  modulus = 2147483647 ## i64
  if which == 0
    return ((u % modulus) * 1009 + (v % modulus) * 9176 + (w % modulus) * 65537 + 17) % modulus
  ((u % modulus) * 131071 + (v % modulus) * 524287 + (w % modulus) * 8191 + 97) % modulus

-> ffbi_identity_view(state, current) (i64[] i64) i64
  rank = ffbi_view_rank(state, current) ## i64
  if rank < 1
    return 0
  n = ffw_n(state) ## i64
  gl = ffbi_gl_invariant_view(state, current) ## i64
  minimum = 9223372036854775807 ## i64
  reverse = 0 ## i64
  while reverse < 2
    code = 0 ## i64
    while code < 6
      sum1 = 0 ## i64
      square1 = 0 ## i64
      sum2 = 0 ## i64
      square2 = 0 ## i64
      bits = 0 ## i64
      i = 0 ## i64
      while i < rank
        source_u = ffbi_view_u(state, i, current) ## i64
        source_v = ffbi_view_v(state, i, current) ## i64
        source_w = ffbi_view_w(state, i, current) ## i64
        transformed_u = ffbi_transform_factor(source_u, source_v, source_w, n, code, reverse, 0) ## i64
        transformed_v = ffbi_transform_factor(source_u, source_v, source_w, n, code, reverse, 1) ## i64
        transformed_w = ffbi_transform_factor(source_u, source_v, source_w, n, code, reverse, 2) ## i64
        h1 = ffbi_term_hash(transformed_u, transformed_v, transformed_w, 0) ## i64
        h2 = ffbi_term_hash(transformed_u, transformed_v, transformed_w, 1) ## i64
        sum1 = (sum1 + h1) % 2147483647
        square1 = (square1 + (h1 * h1) % 2147483647) % 2147483647
        sum2 = (sum2 + h2) % 2147483647
        square2 = (square2 + (h2 * h2) % 2147483647) % 2147483647
        bits += ffw_popcount(transformed_u) + ffw_popcount(transformed_v) + ffw_popcount(transformed_w)
        i += 1
      digest1 = (sum1 * 65537 + square1 + rank * 8191 + bits * 127 + gl) % 2147483647 ## i64
      digest2 = (sum2 * 1009 + square2 + rank * 131071 + bits * 31 + gl * 17) % 2147483647 ## i64
      candidate = (digest1 << 31) ^ digest2 ## i64
      if candidate < minimum
        minimum = candidate
      code += 1
    reverse += 1
  minimum

-> ffbi_best_id(state) (i64[]) i64
  ffbi_identity_view(state, 0)

-> ffbi_current_id(state) (i64[]) i64
  ffbi_identity_view(state, 1)

-> ffbi_best_current_equivalent(best, current) (i64[] i64[]) i64
  same = 0 ## i64
  if ffbi_best_id(best) == ffbi_current_id(current)
    same = 1
  same
