# Exact cross-format projection/replacement tunnel.
#
# For an exact square scheme S and any exact scheme B one size lower, let P(S)
# be the termwise coordinate projection.  Embedded back into the large tensor,
# P(S) and B represent the same lower matrix-multiplication tensor, hence
#
#   S XOR embed(P(S)) XOR embed(B) = S.
#
# Canonical GF(2) toggling removes identical triples.  The resulting endpoint
# may carry rank debt, but it changes an entire lower-dimensional core in one
# exact move and can therefore cross components unavailable to local flips.

use flipfleet_projection_boundary_repair

# meta: source rank, projected rank, replacement rank, final rank, debt,
# zero projected terms, raw cancellation count, exact gate.
-> ffpr_splice(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, d, out_u, out_v, out_w, capacity, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 8
    meta[i] = 0
    i += 1
  if n < 3 || n > 7 || d < 2 || d >= n || source_rank < 1 || lower_rank < 1 || source_rank + source_rank + lower_rank > capacity
    return 0
  if ffpbr_verify_exact(source_u, source_v, source_w, source_rank, n, n, n) != 1
    return 0
  if ffpbr_verify_exact(lower_u, lower_v, lower_w, lower_rank, d, d, d) != 1
    return 0

  core_u = i64[capacity]
  core_v = i64[capacity]
  core_w = i64[capacity]
  boundary_u = i64[capacity]
  boundary_v = i64[capacity]
  boundary_w = i64[capacity]
  projected_u = i64[capacity]
  projected_v = i64[capacity]
  projected_w = i64[capacity]
  project_meta = i64[8]
  projected_rank = ffpbr_project_square(source_u, source_v, source_w, source_rank, n, d, d, d, core_u, core_v, core_w, boundary_u, boundary_v, boundary_w, projected_u, projected_v, projected_w, capacity, project_meta) ## i64
  if projected_rank < 1 || project_meta[6] != 1
    return 0

  final_rank = 0 ## i64
  t = 0 ## i64
  while t < source_rank
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, source_u[t], source_v[t], source_w[t])
    t += 1
  t = 0
  while t < projected_rank
    u = ffpbr_embed_factor(projected_u[t], d, d, n, n) ## i64
    v = ffpbr_embed_factor(projected_v[t], d, d, n, n) ## i64
    w = ffpbr_embed_factor(projected_w[t], d, d, n, n) ## i64
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1
  t = 0
  while t < lower_rank
    u = ffpbr_embed_factor(lower_u[t], d, d, n, n)
    v = ffpbr_embed_factor(lower_v[t], d, d, n, n)
    w = ffpbr_embed_factor(lower_w[t], d, d, n, n)
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1

  meta[0] = source_rank
  meta[1] = projected_rank
  meta[2] = lower_rank
  meta[3] = final_rank
  meta[4] = final_rank - source_rank
  meta[5] = project_meta[3]
  meta[6] = source_rank + projected_rank + lower_rank - final_rank
  if final_rank > 0 && ffpbr_verify_exact(out_u, out_v, out_w, final_rank, n, n, n) == 1
    meta[7] = 1
    return final_rank
  0

# Fixed-size indexed projection/embedding for exhaustive 2x2 core placement.
# r0<r1 and c0<c1 select ambient row/column coordinates.
-> ffpr_project2_factor(mask, n, r0, r1, c0, c1) (i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  if ((mask >> (r0 * n + c0)) & 1) != 0
    result = result | 1
  if ((mask >> (r0 * n + c1)) & 1) != 0
    result = result | 2
  if ((mask >> (r1 * n + c0)) & 1) != 0
    result = result | 4
  if ((mask >> (r1 * n + c1)) & 1) != 0
    result = result | 8
  result

-> ffpr_embed2_factor(mask, n, r0, r1, c0, c1) (i64 i64 i64 i64 i64 i64) i64
  result = 0 ## i64
  if (mask & 1) != 0
    result = result | (1 << (r0 * n + c0))
  if (mask & 2) != 0
    result = result | (1 << (r0 * n + c1))
  if (mask & 4) != 0
    result = result | (1 << (r1 * n + c0))
  if (mask & 8) != 0
    result = result | (1 << (r1 * n + c1))
  result

# General coordinate-subspace projection/embedding.  The row/column index
# lists are strictly increasing ambient coordinates and define the same
# left-inverse pair used by the specialized 2x2 path above.
-> ffpr_project_indexed_factor(mask, n, d, rows, cols) (i64 i64 i64 i64[] i64[]) i64
  result = 0 ## i64
  r = 0 ## i64
  while r < d
    c = 0 ## i64
    while c < d
      if ((mask >> (rows[r] * n + cols[c])) & 1) != 0
        result = result | (1 << (r * d + c))
      c += 1
    r += 1
  result

-> ffpr_embed_indexed_factor(mask, n, d, rows, cols) (i64 i64 i64 i64[] i64[]) i64
  result = 0 ## i64
  r = 0 ## i64
  while r < d
    c = 0 ## i64
    while c < d
      if ((mask >> (r * d + c)) & 1) != 0
        result = result | (1 << (rows[r] * n + cols[c]))
      c += 1
    r += 1
  result

# General indexed square-core splice.  This is the audit/seed-generation
# path for d>2; the hot 2x2 campaign probe keeps its unrolled helper.
-> ffpr_splice_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, d, indices_i, indices_j, indices_k, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, verify, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
  x = 0 ## i64
  while x < 8
    meta[x] = 0
    x += 1
  if n < 3 || n > 7 || d < 2 || d >= n || lower_rank < 1 || source_rank + source_rank + lower_rank > capacity
    return 0

  projected_rank = 0 ## i64
  zero_count = 0 ## i64
  t = 0 ## i64
  while t < source_rank
    u = ffpr_project_indexed_factor(source_u[t], n, d, indices_i, indices_j) ## i64
    v = ffpr_project_indexed_factor(source_v[t], n, d, indices_j, indices_k) ## i64
    w = ffpr_project_indexed_factor(source_w[t], n, d, indices_i, indices_k) ## i64
    if u == 0 || v == 0 || w == 0
      zero_count += 1
    else
      projected_rank = ffsdr_toggle_term(projected_u, projected_v, projected_w, projected_rank, u, v, w)
    t += 1

  final_rank = 0 ## i64
  t = 0
  while t < source_rank
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, source_u[t], source_v[t], source_w[t])
    t += 1
  t = 0
  while t < projected_rank
    u = ffpr_embed_indexed_factor(projected_u[t], n, d, indices_i, indices_j)
    v = ffpr_embed_indexed_factor(projected_v[t], n, d, indices_j, indices_k)
    w = ffpr_embed_indexed_factor(projected_w[t], n, d, indices_i, indices_k)
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1
  t = 0
  while t < lower_rank
    u = ffpr_embed_indexed_factor(lower_u[t], n, d, indices_i, indices_j)
    v = ffpr_embed_indexed_factor(lower_v[t], n, d, indices_j, indices_k)
    w = ffpr_embed_indexed_factor(lower_w[t], n, d, indices_i, indices_k)
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1

  meta[0] = source_rank
  meta[1] = projected_rank
  meta[2] = lower_rank
  meta[3] = final_rank
  meta[4] = final_rank - source_rank
  meta[5] = zero_count
  meta[6] = source_rank + projected_rank + lower_rank - final_rank
  if verify == 0
    return final_rank
  if final_rank > 0 && ffpbr_verify_exact(out_u, out_v, out_w, final_rank, n, n, n) == 1
    meta[7] = 1
    return final_rank
  0

# Fast indexed 2x2 splice for an already full-gated source and replacement.
# Scratch/output arrays are caller-owned and reusable across a placement scan.
# meta: source, projected, replacement, final, debt, zero projections,
# cancellations, optional exact gate.
-> ffpr_splice2_indexed(source_u, source_v, source_w, source_rank, lower_u, lower_v, lower_w, lower_rank, n, i0, i1, j0, j1, k0, k1, projected_u, projected_v, projected_w, out_u, out_v, out_w, capacity, verify, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
  x = 0 ## i64
  while x < 8
    meta[x] = 0
    x += 1
  if n < 3 || n > 7 || lower_rank < 1 || source_rank + source_rank + lower_rank > capacity
    return 0
  projected_rank = 0 ## i64
  zero_count = 0 ## i64
  t = 0 ## i64
  while t < source_rank
    u = ffpr_project2_factor(source_u[t], n, i0, i1, j0, j1) ## i64
    v = ffpr_project2_factor(source_v[t], n, j0, j1, k0, k1) ## i64
    w = ffpr_project2_factor(source_w[t], n, i0, i1, k0, k1) ## i64
    if u == 0 || v == 0 || w == 0
      zero_count += 1
    else
      projected_rank = ffsdr_toggle_term(projected_u, projected_v, projected_w, projected_rank, u, v, w)
    t += 1

  final_rank = 0 ## i64
  t = 0
  while t < source_rank
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, source_u[t], source_v[t], source_w[t])
    t += 1
  t = 0
  while t < projected_rank
    u = ffpr_embed2_factor(projected_u[t], n, i0, i1, j0, j1)
    v = ffpr_embed2_factor(projected_v[t], n, j0, j1, k0, k1)
    w = ffpr_embed2_factor(projected_w[t], n, i0, i1, k0, k1)
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1
  t = 0
  while t < lower_rank
    u = ffpr_embed2_factor(lower_u[t], n, i0, i1, j0, j1)
    v = ffpr_embed2_factor(lower_v[t], n, j0, j1, k0, k1)
    w = ffpr_embed2_factor(lower_w[t], n, i0, i1, k0, k1)
    final_rank = ffsdr_toggle_term(out_u, out_v, out_w, final_rank, u, v, w)
    t += 1

  meta[0] = source_rank
  meta[1] = projected_rank
  meta[2] = lower_rank
  meta[3] = final_rank
  meta[4] = final_rank - source_rank
  meta[5] = zero_count
  meta[6] = source_rank + projected_rank + lower_rank - final_rank
  if verify == 0
    return final_rank
  if ffpbr_verify_exact(out_u, out_v, out_w, final_rank, n, n, n) == 1
    meta[7] = 1
    return final_rank
  0
