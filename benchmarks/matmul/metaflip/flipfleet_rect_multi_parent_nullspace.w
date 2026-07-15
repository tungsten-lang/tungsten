# Complete affine nullspace search over the unique term union of two or more
# exact rectangular GF(2) schemes.  Starting from parent zero's term mask,
# every kernel vector toggles to another subset with the same tensor.  This
# exposes correlated relations involving three or more parents which no
# pairwise parent-difference search can see.

use flipfleet_rect_archive_nullspace

-> ffrmp_find(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> ffrmp_add_scheme(us, vs, ws, count, capacity, scheme) (i64[] i64[] i64[] i64 i64 FFBCScheme) i64
  i = 0 ## i64
  while i < scheme.rank()
    if ffrmp_find(us, vs, ws, count, scheme.us()[i], scheme.vs()[i], scheme.ws()[i]) < 0
      if count >= capacity
        return 0 - 1
      us[count] = scheme.us()[i]
      vs[count] = scheme.vs()[i]
      ws[count] = scheme.ws()[i]
      count += 1
    i += 1
  count

-> ffrmp_weight(mask, count) (i64[] i64) i64
  weight = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, 0, i) != 0
      weight += 1
    i += 1
  weight

-> ffrmp_materialize(us, vs, ws, count, mask, rank, n, m, p) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64)
  if rank < 1
    return nil
  child = FFBCScheme.new(n, m, p, rank)
  slot = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, 0, i) != 0
      if slot >= rank
        return nil
      child.us()[slot] = us[i]
      child.vs()[slot] = vs[i]
      child.ws()[slot] = ws[i]
      slot += 1
    i += 1
  if slot != rank
    return nil
  child.set_rank(rank)
  child

# Enumerate the complete affine solution coset when nullity <= max_nullity.
# All subsets of size at most max_rank are independently reconstructed.
# meta: parents, union, column rank, nullity, affine solutions, gated,
# lower-than-anchor, equal-to-anchor, best rank, best density, gate failures,
# best relation code, exhaustive flag.
-> ffrmp_search(parents, n, m, p, max_nullity, max_rank, meta) (Array i64 i64 i64 i64 i64 i64[])
  if parents.size() < 2 || max_nullity < 1 || max_nullity > 24 || max_rank < 1
    return nil
  anchor = parents[0]
  if anchor == nil || anchor.n() != n || anchor.m() != m || anchor.p() != p || anchor.rank() > max_rank
    return nil
  capacity = 0 ## i64
  i = 0 ## i64
  while i < parents.size()
    parent = parents[i]
    if parent == nil || parent.n() != n || parent.m() != m || parent.p() != p || parent.uw() != 1 || parent.vw() != 1 || parent.ww() != 1 || ffbc_verify_exact(parent) != 1
      return nil
    capacity += parent.rank()
    i += 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  count = 0 ## i64
  i = 0
  while i < parents.size()
    count = ffrmp_add_scheme(us, vs, ws, count, capacity, parents[i])
    if count < 1
      return nil
    i += 1

  combo_words = ffnd_combo_words(count) ## i64
  anchor_mask = i64[combo_words]
  i = 0
  while i < anchor.rank()
    index = ffrmp_find(us, vs, ws, count, anchor.us()[i], anchor.vs()[i], anchor.ws()[i]) ## i64
    if index < 0
      return nil
    z = ffnd_set_mask_bit(anchor_mask, 0, index) ## i64
    i += 1
  if ffrmp_weight(anchor_mask, count) != anchor.rank()
    return nil

  basis = i64[count * combo_words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(us, vs, ws, count, n, m, p, basis, elimination) ## i64
  meta[0] = parents.size()
  meta[1] = count
  meta[2] = elimination[2]
  meta[3] = nullity
  if nullity < 1 || elimination[2] + nullity != count || nullity > max_nullity
    return nil

  limit = 1 << nullity ## i64
  meta[4] = limit
  candidate = i64[combo_words]
  best = nil
  best_rank = 0x7fffffff ## i64
  best_density = 0x7fffffff ## i64
  code = 0 ## i64
  while code < limit
    z = ffnd_copy(anchor_mask, 0, candidate, 0, combo_words) ## i64
    bit = 0 ## i64
    while bit < nullity
      if ((code >> bit) & 1) != 0
        z = ffnd_xor(basis, bit * combo_words, candidate, 0, combo_words)
      bit += 1
    weight = ffrmp_weight(candidate, count) ## i64
    if weight <= max_rank
      child = ffrmp_materialize(us, vs, ws, count, candidate, weight, n, m, p)
      meta[5] += 1
      if child == nil || ffbc_verify_exact(child) != 1
        meta[10] += 1
        return nil
      if weight < anchor.rank()
        meta[6] += 1
      if weight == anchor.rank()
        meta[7] += 1
      density = fflc_density(child) ## i64
      if weight < best_rank || (weight == best_rank && density < best_density)
        best = fflc_clone(child)
        best_rank = weight
        best_density = density
        meta[11] = code
    code += 1
  meta[8] = best_rank
  meta[9] = best_density
  meta[12] = 1
  best
