# Linear images of archive zero relations.
#
# If A and B are exact schemes for the same tensor, Z=A XOR B represents zero.
# For arbitrary linear factor maps P,Q,R, (P tensor Q tensor R)Z is still zero,
# even when the maps are singular and are not matrix-multiplication tensor
# automorphisms.  Toggling that image into a leader is therefore an exact move.
# This is broader than affine parent XOR (the image need not be another parent)
# and differs from selected-subset factor-map nullspaces (no kernel solve is
# needed: the complete archive difference is already a certified relation).

use flipfleet_factor_map_nullspace

-> ffzri_copy(source_u, source_v, source_w, target_u, target_v, target_w, offset, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target_u[offset + i] = source_u[i]
    target_v[offset + i] = source_v[i]
    target_w[offset + i] = source_w[i]
    i += 1
  count

# Canonical parity difference A XOR B. meta counts zeros and cancellations.
-> ffzri_relation(a_u, a_v, a_w, a_rank, b_u, b_v, b_w, b_rank, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if raw_u.size() < a_rank + b_rank || raw_v.size() < a_rank + b_rank || raw_w.size() < a_rank + b_rank
    return 0 - 1
  ffzri_copy(a_u, a_v, a_w, raw_u, raw_v, raw_w, 0, a_rank)
  ffzri_copy(b_u, b_v, b_w, raw_u, raw_v, raw_w, a_rank, b_rank)
  ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, a_rank + b_rank, out_u, out_v, out_w, meta)

# Apply one raw one-factor operation to a complete zero relation and compact
# zero factors / duplicate images by parity.
-> ffzri_map_relation(z_u, z_v, z_w, z_rank, factor, operation, source, target, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  transformed = i64[3]
  i = 0 ## i64
  while i < z_rank
    if ffmfn_transform_term(z_u[i], z_v[i], z_w[i], factor, operation, source, target, transformed) != 1
      return 0 - 1
    raw_u[i] = transformed[0]
    raw_v[i] = transformed[1]
    raw_w[i] = transformed[2]
    i += 1
  ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, z_rank, out_u, out_v, out_w, meta)

-> ffzri_term_density(u, v, w) (i64 i64 i64) i64
  ffw_popcount(u) + ffw_popcount(v) + ffw_popcount(w)

-> ffzri_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffzri_term_density(us[i], vs[i], ws[i])
    i += 1
  density

# Independent tensor-zero check used by planted controls and final audit
# winners.  This is intentionally not called for every scored map.
-> ffzri_zero_tensor(us, vs, ws, rank, n) (i64[] i64[] i64[] i64 i64) i64
  words = ffpa_tensor_words(n) ## i64
  tensor = i64[words]
  i = 0 ## i64
  while i < rank
    ffpa_xor_outer(tensor, 0, us[i], vs[i], ws[i], n)
    i += 1
  word = 0 ## i64
  while word < words
    if tensor[word] != 0
      return 0
    word += 1
  1

-> ffzri_find(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

# Score leader XOR image without reconstructing it. out = rank, density,
# leader distance, overlap.
-> ffzri_score(leader_u, leader_v, leader_w, leader_rank, leader_density, image_u, image_v, image_w, image_rank, out) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  overlap = 0 ## i64
  overlap_density = 0 ## i64
  image_density = 0 ## i64
  i = 0 ## i64
  while i < image_rank
    term_density = ffzri_term_density(image_u[i], image_v[i], image_w[i]) ## i64
    image_density += term_density
    if ffzri_find(leader_u, leader_v, leader_w, leader_rank, image_u[i], image_v[i], image_w[i]) >= 0
      overlap += 1
      overlap_density += term_density
    i += 1
  out[0] = leader_rank + image_rank - 2 * overlap
  out[1] = leader_density + image_density - 2 * overlap_density
  out[2] = image_rank
  out[3] = overlap
  1

# Materialize leader XOR an already compact image relation.
-> ffzri_toggle_image(leader_u, leader_v, leader_w, leader_rank, image_u, image_v, image_w, image_rank, raw_u, raw_v, raw_w, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if raw_u.size() < leader_rank + image_rank || raw_v.size() < leader_rank + image_rank || raw_w.size() < leader_rank + image_rank
    return 0 - 1
  ffzri_copy(leader_u, leader_v, leader_w, raw_u, raw_v, raw_w, 0, leader_rank)
  ffzri_copy(image_u, image_v, image_w, raw_u, raw_v, raw_w, leader_rank, image_rank)
  ffmfn_compact_allow_zero(raw_u, raw_v, raw_w, leader_rank + image_rank, out_u, out_v, out_w, meta)

# Pick up to `wanted` raw coordinates with the largest occurrence count in one
# relation factor. Ties prefer the smaller coordinate for reproducibility.
-> ffzri_top_coordinates(z_u, z_v, z_w, z_rank, factor, dimension, wanted, out) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  count = wanted ## i64
  if count > dimension
    count = dimension
  if count > out.size()
    count = out.size()
  occurrences = i64[dimension]
  i = 0 ## i64
  while i < z_rank
    value = z_u[i] ## i64
    if factor == 1
      value = z_v[i]
    if factor == 2
      value = z_w[i]
    coordinate = 0 ## i64
    while coordinate < dimension
      if ((value >> coordinate) & 1) != 0
        occurrences[coordinate] = occurrences[coordinate] + 1
      coordinate += 1
    i += 1
  made = 0 ## i64
  while made < count
    chosen = 0 - 1 ## i64
    coordinate = 0
    while coordinate < dimension
      used = 0 ## i64
      prior = 0 ## i64
      while prior < made
        if out[prior] == coordinate
          used = 1
        prior += 1
      if used == 0
        if chosen < 0 || occurrences[coordinate] > occurrences[chosen]
          chosen = coordinate
      coordinate += 1
    if chosen < 0
      return made
    out[made] = chosen
    made += 1
  made
