# Exact selected-subset replacements under simultaneous raw linear maps on all
# three rank-one factor spaces.
#
# For fixed linear maps A, B, C and each live term t = u (x) v (x) w, form
#
#   d(t) = t XOR (A u) (x) (B v) (x) (C w).
#
# Any coefficient-nullspace relation XOR_{t in S} d(t) = 0 proves that the
# atomic replacement S -> (A (x) B (x) C)S preserves the represented tensor.
# Unlike the one- and two-factor map workers, this complete row contains the
# cubic cross term.  It cannot be reconstructed by XORing the three one-factor
# rows or any collection of pair rows.
#
# Plans have twelve words, grouped by factor U/V/W:
#   [axis, operation, source, target] * 3.
# Operations are the raw swap/shear/delete/fold maps from
# flipfleet_factor_map_nullspace.w.  Singular images containing a zero factor
# are the additive zero and are omitted before parity compaction.

use flipfleet_two_factor_map_nullspace

-> ff3m_valid_plan(dimension, plan) (i64 i64[]) i64
  if dimension < 2 || plan.size() < 12
    return 0
  axis = 0 ## i64
  while axis < 3
    offset = axis * 4 ## i64
    # Four-word spacing keeps plans source-compatible with the paired-map
    # representation: axis, operation, source, target.
    if plan[offset] != axis
      return 0
    if fftfn_valid_map(dimension, plan[offset + 1], plan[offset + 2], plan[offset + 3]) != 1
      return 0
    axis += 1
  1

-> ff3m_transform_term(u, v, w, dimension, plan, out) (i64 i64 i64 i64 i64[] i64[]) i64
  if out.size() < 3 || ff3m_valid_plan(dimension, plan) != 1
    return 0
  out[0] = ffmfn_map_factor(u, plan[1], plan[2], plan[3])
  out[1] = ffmfn_map_factor(v, plan[5], plan[6], plan[7])
  out[2] = ffmfn_map_factor(w, plan[9], plan[10], plan[11])
  1

-> ff3m_build_deltas(us, vs, ws, rank, n, plan, transformed_u, transformed_v, transformed_w, deltas) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  dimension = n * n ## i64
  words = ffpa_tensor_words(n) ## i64
  if rank < 1 || ff3m_valid_plan(dimension, plan) != 1
    return 0
  if transformed_u.size() < rank || transformed_v.size() < rank || transformed_w.size() < rank || deltas.size() < rank * words
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if ff3m_transform_term(us[i], vs[i], ws[i], dimension, plan, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    z = ffpa_clear_row(deltas, i * words, words) ## i64
    z = ffpa_xor_outer(deltas, i * words, us[i], vs[i], ws[i], n)
    if out[0] != 0 && out[1] != 0 && out[2] != 0
      z = ffpa_xor_outer(deltas, i * words, out[0], out[1], out[2], n)
    i += 1
  words

-> ff3m_transform_terms(us, vs, ws, rank, n, plan, transformed_u, transformed_v, transformed_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  dimension = n * n ## i64
  if rank < 1 || ff3m_valid_plan(dimension, plan) != 1
    return 0
  if transformed_u.size() < rank || transformed_v.size() < rank || transformed_w.size() < rank
    return 0
  out = i64[3]
  i = 0 ## i64
  while i < rank
    if ff3m_transform_term(us[i], vs[i], ws[i], dimension, plan, out) != 1
      return 0
    transformed_u[i] = out[0]
    transformed_v[i] = out[1]
    transformed_w[i] = out[2]
    i += 1
  rank

# Exact GF(2)-parity comparison between the selected source set and its image.
# The older automorphism helper assumes an injective map.  Raw delete/fold
# maps are singular, so two images may collide or vanish; membership alone
# would incorrectly call such a multiset a no-op.  This routine explicitly
# checks odd image multiplicity for every selected source term and rejects any
# odd image term outside the selected source set.
-> ff3m_selected_image_same_parity(us, vs, ws, transformed_u, transformed_v, transformed_w, ids, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if count < 1 || ids.size() < count
    return 0
  same = 1 ## i64
  source_index = 0 ## i64
  while source_index < count && same == 1
    source = ids[source_index] ## i64
    parity = 0 ## i64
    image_index = 0 ## i64
    while image_index < count
      image = ids[image_index] ## i64
      if transformed_u[image] == us[source] && transformed_v[image] == vs[source] && transformed_w[image] == ws[source]
        parity = parity ^ 1
      image_index += 1
    if parity == 0
      same = 0
    source_index += 1
  image_index = 0
  while image_index < count && same == 1
    image = ids[image_index] ## i64
    if transformed_u[image] != 0 && transformed_v[image] != 0 && transformed_w[image] != 0
      in_source = 0 ## i64
      source_index = 0
      while source_index < count
        source = ids[source_index] ## i64
        if transformed_u[image] == us[source] && transformed_v[image] == vs[source] && transformed_w[image] == ws[source]
          in_source = 1
        source_index += 1
      if in_source == 0
        parity = 0
        peer_index = 0 ## i64
        while peer_index < count
          peer = ids[peer_index] ## i64
          if transformed_u[peer] == transformed_u[image] && transformed_v[peer] == transformed_v[image] && transformed_w[peer] == transformed_w[image]
            parity = parity ^ 1
          peer_index += 1
        if parity != 0
          same = 0
    image_index += 1
  same

# Materialization is identical to the paired-map case once all three images
# have been computed.  Keep a named entry point so tests and future pool code
# do not need to know that implementation detail.
-> ff3m_materialize(us, vs, ws, rank, transformed_u, transformed_v, transformed_w, ids, made, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  fftfn_materialize(us, vs, ws, rank, transformed_u, transformed_v, transformed_w, ids, made, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta)
