# Exact selected-subset replacements under simultaneous raw linear maps on two
# rank-one factor spaces.
#
# For distinct factor axes a,b and fixed linear maps A,B, each live term has
# the complete delta
#
#   d(t) = t XOR (A on a, B on b)(t).
#
# A nullspace vector of these deltas proves an exact atomic replacement.  The
# complete delta is essential: when both factors change it contains the
# bilinear cross term and is not the XOR of the two one-factor deltas.  Maps
# may be invertible (raw coordinate swaps/shears) or singular
# (delete/fold projections).  A singular image with any zero factor is the
# additive zero and is omitted before GF(2) parity compaction.

use flipfleet_factor_map_nullspace

-> fftfn_valid_map(dimension, operation, source, target) (i64 i64 i64 i64) i64
  if dimension < 2 || operation < 0 || operation > 3 || source < 0 || source >= dimension
    return 0
  if operation != 2
    if target < 0 || target >= dimension || target == source
      return 0
  1

-> fftfn_transform_term(u, v, w, dimension, plan, out) (i64 i64 i64 i64 i64[] i64[]) i64
  if plan.size() < 8
    return 0
  axis_a = plan[0] ## i64
  operation_a = plan[1] ## i64
  source_a = plan[2] ## i64
  target_a = plan[3] ## i64
  axis_b = plan[4] ## i64
  operation_b = plan[5] ## i64
  source_b = plan[6] ## i64
  target_b = plan[7] ## i64
  if out.size() < 3 || axis_a < 0 || axis_a > 2 || axis_b < 0 || axis_b > 2 || axis_a == axis_b
    return 0
  if fftfn_valid_map(dimension, operation_a, source_a, target_a) != 1 || fftfn_valid_map(dimension, operation_b, source_b, target_b) != 1
    return 0
  out[0] = u
  out[1] = v
  out[2] = w
  if axis_a == 0
    out[0] = ffmfn_map_factor(out[0], operation_a, source_a, target_a)
  if axis_a == 1
    out[1] = ffmfn_map_factor(out[1], operation_a, source_a, target_a)
  if axis_a == 2
    out[2] = ffmfn_map_factor(out[2], operation_a, source_a, target_a)
  if axis_b == 0
    out[0] = ffmfn_map_factor(out[0], operation_b, source_b, target_b)
  if axis_b == 1
    out[1] = ffmfn_map_factor(out[1], operation_b, source_b, target_b)
  if axis_b == 2
    out[2] = ffmfn_map_factor(out[2], operation_b, source_b, target_b)
  1

-> fftfn_build_deltas(us, vs, ws, rank, n, plan, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  dimension = n * n ## i64
  words = ffpa_tensor_words(n) ## i64
  if rank < 1 || plan.size() < 8 || transformed_u.size() < rank || transformed_v.size() < rank || transformed_w.size() < rank || deltas.size() < rank * words
    return 0
  axis_a = plan[0] ## i64
  operation_a = plan[1] ## i64
  source_a = plan[2] ## i64
  target_a = plan[3] ## i64
  axis_b = plan[4] ## i64
  operation_b = plan[5] ## i64
  source_b = plan[6] ## i64
  target_b = plan[7] ## i64
  if axis_a < 0 || axis_a > 2 || axis_b < 0 || axis_b > 2 || axis_a == axis_b
    return 0
  if fftfn_valid_map(dimension, operation_a, source_a, target_a) != 1 || fftfn_valid_map(dimension, operation_b, source_b, target_b) != 1
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if fftfn_transform_term(us[i], vs[i], ws[i], dimension, plan, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    z = ffpa_clear_row(deltas, i * words, words) ## i64
    z = ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
    # A zero factor is the zero tensor, so its outer product contributes no
    # coefficient to the complete old-XOR-new row.
    if out[0] != 0 && out[1] != 0 && out[2] != 0
      z = ffpa_xor_outer(deltas, i * words, out[0], out[1], out[2], n)
    i += 1
  words

-> fftfn_transform_terms(us, vs, ws, rank, n, plan, transformed_u, transformed_v, transformed_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  dimension = n * n ## i64
  if rank < 1 || plan.size() < 8 || transformed_u.size() < rank || transformed_v.size() < rank || transformed_w.size() < rank
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if fftfn_transform_term(us[i], vs[i], ws[i], dimension, plan, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    i += 1
  rank

# Replace exactly the selected source positions by their already-computed
# paired images, omit zero tensors, and parity-cancel duplicate triples.
# meta: omitted zeros, duplicate-pair removals, selected positions.
-> fftfn_materialize(us, vs, ws, rank, transformed_u, transformed_v, transformed_w, ids, made, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 1 || made < 1 || meta.size() < 3
    return 0 - 1
  if raw_u.size() < rank || raw_v.size() < rank || raw_w.size() < rank || out_u.size() < rank || out_v.size() < rank || out_w.size() < rank
    return 0 - 1
  z = ffpan_copy_terms(us, vs, ws, raw_u, raw_v, raw_w, rank) ## i64
  i = 0 ## i64
  while i < made
    position = ids[i] ## i64
    if position < 0 || position >= rank
      return 0 - 1
    raw_u[position] = transformed_u[position]
    raw_v[position] = transformed_v[position]
    raw_w[position] = transformed_w[position]
    i += 1
  compact_meta = i64[2]
  endpoint_rank = ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w, compact_meta) ## i64
  meta[0] = compact_meta[0]
  meta[1] = compact_meta[1]
  meta[2] = made
  endpoint_rank
