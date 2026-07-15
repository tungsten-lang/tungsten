# Exact square-to-rectangular projection with explicit boundary repair.
#
# Restricting the three matrix-index domains is a tensor homomorphism:
#   U=(I,K) -> (n,m), V=(K,J) -> (m,p), W=(I,J) -> (n,p).
# The projected decomposition is therefore exact after zero terms and XOR
# duplicates are removed.  Terms whose source support touches a discarded
# coordinate are retained in a separate boundary component.  The tensor
# residual of the projected core is compared word-for-word with that boundary
# component; no random evaluation is used.
#
# `ffpbr_repair_boundary` removes a marked 3- or 4-term boundary window and
# invokes the complete span MITM engine for a k->k-1 completion.  A candidate
# is admitted only after exhaustive reconstruction of the entire rectangular
# multiplication tensor.  Failure leaves an exact copy of the input scheme.

use flipfleet_sat_destroy_repair
use metaflip_rect_worker

-> ffpbr_factor_mask(width) (i64) i64
  if width >= 63
    return 0 - 1
  (1 << width) - 1

-> ffpbr_project_factor(mask, source_rows, source_cols, dest_rows, dest_cols) (i64 i64 i64 i64 i64) i64
  if source_rows < 1 || source_cols < 1 || dest_rows < 1 || dest_cols < 1
    return 0
  if dest_rows > source_rows || dest_cols > source_cols || source_rows * source_cols > 49
    return 0
  result = 0 ## i64
  row = 0 ## i64
  while row < dest_rows
    col = 0 ## i64
    while col < dest_cols
      if ((mask >> (row * source_cols + col)) & 1) != 0
        result = result | (1 << (row * dest_cols + col))
      col += 1
    row += 1
  result

-> ffpbr_embed_factor(mask, source_rows, source_cols, dest_rows, dest_cols) (i64 i64 i64 i64 i64) i64
  if source_rows < 1 || source_cols < 1 || dest_rows < source_rows || dest_cols < source_cols
    return 0
  result = 0 ## i64
  row = 0 ## i64
  while row < source_rows
    col = 0 ## i64
    while col < source_cols
      if ((mask >> (row * source_cols + col)) & 1) != 0
        result = result | (1 << (row * dest_cols + col))
      col += 1
    row += 1
  result

-> ffpbr_factor_touches_dropped(mask, source_rows, source_cols, dest_rows, dest_cols) (i64 i64 i64 i64 i64) i64
  touched = 0 ## i64
  row = 0 ## i64
  while row < source_rows
    col = 0 ## i64
    while col < source_cols
      if row >= dest_rows || col >= dest_cols
        if ((mask >> (row * source_cols + col)) & 1) != 0
          touched = 1
      col += 1
    row += 1
  touched

-> ffpbr_verify_exact(us, vs, ws, rank, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if rank < 1 || n < 1 || m < 1 || p < 1
    return 0
  ab = n * m ## i64
  bc = m * p ## i64
  ac = n * p ## i64
  if ab > 49 || bc > 49 || ac > 49
    return 0
  umask = ffpbr_factor_mask(ab) ## i64
  vmask = ffpbr_factor_mask(bc) ## i64
  wmask = ffpbr_factor_mask(ac) ## i64
  t = 0 ## i64
  while t < rank
    if us[t] <= 0 || vs[t] <= 0 || ws[t] <= 0
      return 0
    if (us[t] & umask) != us[t] || (vs[t] & vmask) != vs[t] || (ws[t] & wmask) != ws[t]
      return 0
    t += 1
  a = 0 ## i64
  while a < ab
    b = 0 ## i64
    while b < bc
      got = 0 ## i64
      t = 0
      while t < rank
        if ((us[t] >> a) & 1) != 0 && ((vs[t] >> b) & 1) != 0
          got = got ^ ws[t]
        t += 1
      expected = 0 ## i64
      if (a % m) == (b / p)
        expected = 1 << ((a / m) * p + (b % p))
      if got != expected
        return 0
      b += 1
    a += 1
  1

-> ffpbr_same_term_sets(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if left_rank != right_rank
    return 0
  i = 0 ## i64
  while i < left_rank
    found = 0 ## i64
    j = 0 ## i64
    while j < right_rank
      if left_u[i] == right_u[j] && left_v[i] == right_v[j] && left_w[i] == right_w[j]
        found = 1
      j += 1
    if found == 0
      return 0
    i += 1
  1

-> ffpbr_copy_scheme(us, vs, ws, rank, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  if rank < 0 || rank > capacity
    return 0
  i = 0 ## i64
  while i < rank
    out_u[i] = us[i]
    out_v[i] = vs[i]
    out_w[i] = ws[i]
    i += 1
  rank

# Split the exact projection into core and discarded-coordinate boundary
# components, then XOR-canonicalize their union.  meta:
# [0] core rank, [1] boundary rank, [2] final rank, [3] zero images,
# [4] source rank, [5] cross-component cancellations, [6] exact gate.
-> ffpbr_project_square(source_u, source_v, source_w, source_rank, square, n, m, p, core_u, core_v, core_w, boundary_u, boundary_v, boundary_w, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  if square < 1 || square > 7 || n < 1 || m < 1 || p < 1 || n > square || m > square || p > square
    return 0
  if source_rank < 1 || source_rank > capacity
    return 0
  if ffpbr_verify_exact(source_u, source_v, source_w, source_rank, square, square, square) != 1
    return 0
  core_rank = 0 ## i64
  boundary_rank = 0 ## i64
  zero_images = 0 ## i64
  t = 0 ## i64
  while t < source_rank
    u = ffpbr_project_factor(source_u[t], square, square, n, m) ## i64
    v = ffpbr_project_factor(source_v[t], square, square, m, p) ## i64
    w = ffpbr_project_factor(source_w[t], square, square, n, p) ## i64
    is_boundary = ffpbr_factor_touches_dropped(source_u[t], square, square, n, m) ## i64
    if ffpbr_factor_touches_dropped(source_v[t], square, square, m, p) == 1
      is_boundary = 1
    if ffpbr_factor_touches_dropped(source_w[t], square, square, n, p) == 1
      is_boundary = 1
    if u == 0 || v == 0 || w == 0
      zero_images += 1
    else
      if is_boundary == 0
        core_rank = ffsdr_toggle_term(core_u, core_v, core_w, core_rank, u, v, w)
      else
        boundary_rank = ffsdr_toggle_term(boundary_u, boundary_v, boundary_w, boundary_rank, u, v, w)
    t += 1
  final_rank = 0 ## i64
  t = 0
  while t < core_rank
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, core_u[t], core_v[t], core_w[t])
    t += 1
  t = 0
  while t < boundary_rank
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, boundary_u[t], boundary_v[t], boundary_w[t])
    t += 1
  meta[0] = core_rank
  meta[1] = boundary_rank
  meta[2] = final_rank
  meta[3] = zero_images
  meta[4] = source_rank
  meta[5] = core_rank + boundary_rank - final_rank
  if final_rank > 0 && ffpbr_verify_exact(out_u, out_v, out_w, final_rank, n, m, p) == 1
    meta[6] = 1
    return final_rank
  0

-> ffpbr_tensor_words(n, m, p) (i64 i64 i64) i64
  ffsdr_tensor_words((n * m) * (m * p) * (n * p))

# residual = MMT(n,m,p) XOR supplied scheme.
-> ffpbr_make_residual(us, vs, ws, rank, n, m, p, residual) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  ab = n * m ## i64
  bc = m * p ## i64
  ac = n * p ## i64
  words = ffpbr_tensor_words(n, m, p) ## i64
  if residual.size() < words
    return 0
  z = ffsdr_clear(residual, words) ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < m
      j = 0 ## i64
      while j < p
        a = i * m + k ## i64
        b = k * p + j ## i64
        c = i * p + j ## i64
        z = ffsdr_toggle_bit(residual, (a * bc + b) * ac + c)
        j += 1
      k += 1
    i += 1
  t = 0 ## i64
  while t < rank
    z = ffsdr_xor_outer(residual, us[t], vs[t], ws[t], ab, bc, ac)
    t += 1
  words

-> ffpbr_boundary_matches_residual(core_u, core_v, core_w, core_rank, boundary_u, boundary_v, boundary_w, boundary_rank, n, m, p) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  words = ffpbr_tensor_words(n, m, p) ## i64
  residual = i64[words]
  boundary_tensor = i64[words]
  if ffpbr_make_residual(core_u, core_v, core_w, core_rank, n, m, p, residual) != words
    return 0
  ab = n * m ## i64
  bc = m * p ## i64
  ac = n * p ## i64
  t = 0 ## i64
  while t < boundary_rank
    z = ffsdr_xor_outer(boundary_tensor, boundary_u[t], boundary_v[t], boundary_w[t], ab, bc, ac) ## i64
    t += 1
  ffsdr_rows_equal(residual, boundary_tensor, words)

-> ffpbr_selected_valid(selected, count, rank, boundary_flags) (i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank || boundary_flags[selected[i]] != 1
      return 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        return 0
      j += 1
    i += 1
  1

-> ffpbr_position_selected(selected, count, position) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == position
      return 1
    i += 1
  0

# Complete span/MITM repair of a caller-marked projected boundary window.
# The output is initialized to the original exact scheme; every failure is a
# nonmutation/rollback.  meta: k,want,candidates,probes,before,after,exact,hit.
-> ffpbr_repair_boundary(us, vs, ws, rank, n, m, p, boundary_flags, selected, k, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  copied = ffpbr_copy_scheme(us, vs, ws, rank, out_u, out_v, out_w, capacity) ## i64
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  meta[0] = k
  meta[1] = k - 1
  meta[4] = rank
  meta[5] = rank
  if copied != rank || (k != 3 && k != 4) || rank > capacity
    return rank
  if ffpbr_verify_exact(us, vs, ws, rank, n, m, p) != 1
    return rank
  if ffpbr_selected_valid(selected, k, rank, boundary_flags) != 1
    return rank
  source_u = i64[4]
  source_v = i64[4]
  source_w = i64[4]
  i = 0
  while i < k
    source_u[i] = us[selected[i]]
    source_v[i] = vs[selected[i]]
    source_w[i] = ws[selected[i]]
    i += 1
  replacement_u = i64[4]
  replacement_v = i64[4]
  replacement_w = i64[4]
  span_meta = i64[12]
  want = k - 1 ## i64
  found = ffsr_find_terms(source_u, source_v, source_w, k, want, replacement_u, replacement_v, replacement_w, span_meta) ## i64
  meta[2] = span_meta[4]
  meta[3] = span_meta[8]
  if found != want
    return rank
  candidate_u = i64[capacity]
  candidate_v = i64[capacity]
  candidate_w = i64[capacity]
  candidate_rank = 0 ## i64
  position = 0 ## i64
  while position < rank
    if ffpbr_position_selected(selected, k, position) == 0
      candidate_rank = ffsdr_toggle_term(candidate_u, candidate_v, candidate_w, candidate_rank, us[position], vs[position], ws[position])
    position += 1
  i = 0
  while i < found
    candidate_rank = ffsdr_toggle_term(candidate_u, candidate_v, candidate_w, candidate_rank, replacement_u[i], replacement_v[i], replacement_w[i])
    i += 1
  if candidate_rank != rank - 1 || ffpbr_verify_exact(candidate_u, candidate_v, candidate_w, candidate_rank, n, m, p) != 1
    return rank
  z = ffpbr_copy_scheme(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w, capacity) ## i64
  meta[5] = candidate_rank
  meta[6] = 1
  meta[7] = 1
  candidate_rank

# Exact geometry roundtrip for a rectangular scheme: zero-embed its factors in
# q-by-q square coordinates, project them back, canonicalize, and full-gate.
-> ffpbr_embed_project_roundtrip(us, vs, ws, rank, n, m, p, square, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  if rank < 1 || rank > capacity || n > square || m > square || p > square
    return 0
  if ffpbr_verify_exact(us, vs, ws, rank, n, m, p) != 1
    return 0
  made = 0 ## i64
  t = 0 ## i64
  while t < rank
    eu = ffpbr_embed_factor(us[t], n, m, square, square) ## i64
    ev = ffpbr_embed_factor(vs[t], m, p, square, square) ## i64
    ew = ffpbr_embed_factor(ws[t], n, p, square, square) ## i64
    pu = ffpbr_project_factor(eu, square, square, n, m) ## i64
    pv = ffpbr_project_factor(ev, square, square, m, p) ## i64
    pw = ffpbr_project_factor(ew, square, square, n, p) ## i64
    made = ffsdr_toggle_term(out_u, out_v, out_w, made, pu, pv, pw)
    t += 1
  if made != rank || ffpbr_verify_exact(out_u, out_v, out_w, made, n, m, p) != 1
    return 0
  if ffpbr_same_term_sets(us, vs, ws, rank, out_u, out_v, out_w, made) != 1
    return 0
  made
