# Exact archive-difference nullspace crossover for rectangular GF(2) schemes.
#
# This is the unequal-factor counterpart of `flipfleet_archive_nullspace.w`.
# It deliberately reuses that module's term-set, provenance-mask, scoring, and
# materialization helpers; only tensor-column expansion and elimination depend
# on the rectangular U/V/W widths.  All supported profile factors fit one
# base-2^30 FFBC limb, while tensor columns are packed into ordinary 64-bit
# elimination words.

use flipfleet_rect_global_isotropy
use flipfleet_archive_nullspace

-> ffran_tensor_words(n, m, p) (i64 i64 i64) i64
  bits = (n * m) * (m * p) * (n * p) ## i64
  (bits + 63) / 64

-> ffran_xor_outer(words, offset, u, v, w, n, m, p) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  udim = n * m ## i64
  vdim = m * p ## i64
  wdim = n * p ## i64
  ai = 0 ## i64
  while ai < udim
    if ((u >> ai) & 1) != 0
      bi = 0 ## i64
      while bi < vdim
        if ((v >> bi) & 1) != 0
          ci = 0 ## i64
          while ci < wdim
            if ((w >> ci) & 1) != 0
              tensor_bit = (ai * vdim + bi) * wdim + ci ## i64
              word = tensor_bit / 64 ## i64
              shift = tensor_bit % 64 ## i64
              words[offset + word] = words[offset + word] ^ (1 << shift)
            ci += 1
        bi += 1
    ai += 1
  1

# `out_basis` stores one ceil(count/64)-word provenance row per dependency.
# meta: tensor words, combination words, column rank, nullity, reductions.
-> ffran_build_nullspace(us, vs, ws, count, n, m, p, out_basis, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[]) i64
  if count < 1 || n < 1 || m < 1 || p < 1
    return 0
  tensor_bits = (n * m) * (m * p) * (n * p) ## i64
  tensor_words = ffran_tensor_words(n, m, p) ## i64
  combo_words = ffnd_combo_words(count) ## i64
  if out_basis.size() < count * combo_words
    return 0
  pivots = i32[tensor_bits]
  pivot_tensors = i64[count * tensor_words]
  pivot_combos = i64[count * combo_words]
  work_tensor = i64[tensor_words]
  work_combo = i64[combo_words]
  column_rank = 0 ## i64
  nullity = 0 ## i64
  reductions = 0 ## i64
  column = 0 ## i64
  while column < count
    z = ffnd_clear(work_tensor, 0, tensor_words) ## i64
    z = ffnd_clear(work_combo, 0, combo_words)
    z = ffran_xor_outer(work_tensor, 0, us[column], vs[column], ws[column], n, m, p)
    z = ffnd_set_mask_bit(work_combo, 0, column)
    reduced = 0 ## i64
    while reduced == 0
      pivot_bit = ffnd_first_set(work_tensor, 0, tensor_words) ## i64
      if pivot_bit < 0
        z = ffnd_copy(work_combo, 0, out_basis, nullity * combo_words, combo_words)
        nullity += 1
        reduced = 1
      if pivot_bit >= 0
        prior = pivots[pivot_bit] - 1 ## i64
        if prior < 0
          z = ffnd_copy(work_tensor, 0, pivot_tensors, column_rank * tensor_words, tensor_words)
          z = ffnd_copy(work_combo, 0, pivot_combos, column_rank * combo_words, combo_words)
          pivots[pivot_bit] = column_rank + 1
          column_rank += 1
          reduced = 1
        if prior >= 0
          z = ffnd_xor(pivot_tensors, prior * tensor_words, work_tensor, 0, tensor_words)
          z = ffnd_xor(pivot_combos, prior * combo_words, work_combo, 0, combo_words)
          reductions += 1
    column += 1
  meta[0] = tensor_words
  meta[1] = combo_words
  meta[2] = column_rank
  meta[3] = nullity
  meta[4] = reductions
  nullity

-> ffran_relation_exact(us, vs, ws, count, n, m, p, mask, mask_offset) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64) i64
  words = ffran_tensor_words(n, m, p) ## i64
  tensor = i64[words]
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, mask_offset, i) != 0
      z = ffran_xor_outer(tensor, 0, us[i], vs[i], ws[i], n, m, p) ## i64
    i += 1
  i = 0
  while i < words
    if tensor[i] != 0
      return 0
    i += 1
  1

# Audit two exact rectangular schemes and materialize the best proper hybrid.
# A nil result with meta[1]==1 is the useful "full difference only" negative.
# meta: difference, nullity, column rank, combinations, child rank, selected,
# A removals, B additions, independent exact child gate.
-> ffran_crossover(left, right, max_combinations, meta) (FFBCScheme FFBCScheme i64 i64[])
  if left == nil || right == nil || max_combinations < 1
    return nil
  if left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return nil
  if left.uw() != 1 || left.vw() != 1 || left.ww() != 1 || right.uw() != 1 || right.vw() != 1 || right.ww() != 1
    return nil
  if ffbc_verify_exact(left) != 1 || ffbc_verify_exact(right) != 1
    return nil

  capacity = left.rank() + right.rank() ## i64
  du = i64[capacity]
  dv = i64[capacity]
  dw = i64[capacity]
  owners = i64[capacity]
  count = ffnd_build_difference(left.us(), left.vs(), left.ws(), left.rank(), right.us(), right.vs(), right.ws(), right.rank(), du, dv, dw, owners) ## i64
  meta[0] = count
  if count < 2
    return nil

  combo_words = ffnd_combo_words(count) ## i64
  basis = i64[count * combo_words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(du, dv, dw, count, left.n(), left.m(), left.p(), basis, elimination) ## i64
  meta[1] = nullity
  meta[2] = elimination[2]
  if nullity < 2
    return nil

  relation = i64[combo_words]
  selection = i64[6]
  projected = ffnd_select_hybrid(basis, nullity, count, owners, left.rank(), max_combinations, relation, selection) ## i64
  meta[3] = selection[0]
  meta[4] = projected
  meta[5] = selection[2]
  meta[6] = selection[3]
  meta[7] = selection[4]
  if projected < 1 || ffran_relation_exact(du, dv, dw, count, left.n(), left.m(), left.p(), relation, 0) != 1
    return nil

  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  child_rank = ffnd_materialize(left.us(), left.vs(), left.ws(), left.rank(), du, dv, dw, count, relation, out_u, out_v, out_w) ## i64
  if child_rank != projected
    return nil
  child = FFBCScheme.new(left.n(), left.m(), left.p(), child_rank)
  i = 0 ## i64
  while i < child_rank
    child.us()[i] = out_u[i]
    child.vs()[i] = out_v[i]
    child.ws()[i] = out_w[i]
    i += 1
  child.set_rank(child_rank)
  if ffbc_verify_exact(child) != 1
    return nil
  meta[8] = 1
  child

# Return the index of a permutation-invariant equal term set in `archive`, or
# -1 when `candidate` is new.  This is intentionally a complete comparison,
# not a Zobrist/fingerprint shortcut: archive-nullspace children are rare and
# exact, so a false collision would throw away precisely the basin diversity
# this move is meant to create.
-> ffran_archive_find(archive, candidate) (Array FFBCScheme) i64
  if candidate == nil
    return 0 - 1
  i = 0 ## i64
  while i < archive.size()
    prior = archive[i]
    if prior != nil && prior.n() == candidate.n() && prior.m() == candidate.m() && prior.p() == candidate.p() && prior.rank() == candidate.rank()
      if fflc_term_set_distance(prior, candidate) == 0
        return i
    i += 1
  0 - 1

# Materialize one already-proved tensor-zero relation as a fresh rectangular
# scheme.  The caller still owns the independent exact gate; keeping this
# helper gate-free lets tests distinguish an elimination/materialization bug
# from a full tensor verification failure.
-> ffran_materialize_relation(left, du, dv, dw, count, relation, projected) (FFBCScheme i64[] i64[] i64[] i64 i64[] i64)
  if left == nil || projected < 1
    return nil
  capacity = left.rank() + count ## i64
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  child_rank = ffnd_materialize(left.us(), left.vs(), left.ws(), left.rank(), du, dv, dw, count, relation, out_u, out_v, out_w) ## i64
  if child_rank != projected
    return nil
  child = FFBCScheme.new(left.n(), left.m(), left.p(), child_rank)
  i = 0 ## i64
  while i < child_rank
    child.us()[i] = out_u[i]
    child.vs()[i] = out_v[i]
    child.ws()[i] = out_w[i]
    i += 1
  child.set_rank(child_rank)
  child

# Enumerate the complete proper kernel hull of one low-nullity parent pair,
# subject to explicit relation and archive-growth caps.  Every materialized
# child receives a full rectangular tensor gate, and `archive` is both the
# output and the complete term-set deduplication set.  Supplying an archive
# that already contains both parents therefore appends only genuinely new
# hybrids, including the complementary child that `ffran_crossover` discards.
#
# `max_nullity` is clamped by contract to 20 so `1 << nullity` is safe and a
# caller cannot accidentally request a giant hull.  `max_combinations` counts
# nonzero kernel vectors; `max_children` bounds additions to `archive`.
#
# meta:
#   0 difference terms, 1 nullity, 2 column rank, 3 hull size,
#   4 relations evaluated, 5 proper relations, 6 materialized,
#   7 exact children, 8 distinct children appended, 9 archive duplicates,
#   10 minimum exact child rank (0 if none), 11 relation cap hit,
#   12 child cap hit, 13 relation failures, 14 materialization failures,
#   15 exact-gate failures.
-> ffran_enumerate_children(left, right, max_nullity, max_combinations, max_children, archive, meta) (FFBCScheme FFBCScheme i64 i64 i64 Array i64[]) i64
  if meta.size() < 16
    return 0
  z = ffnd_clear(meta, 0, 16) ## i64
  if left == nil || right == nil || max_nullity < 2 || max_nullity > 20 || max_combinations < 1 || max_children < 1
    return 0
  if left.n() != right.n() || left.m() != right.m() || left.p() != right.p()
    return 0
  if left.uw() != 1 || left.vw() != 1 || left.ww() != 1 || right.uw() != 1 || right.vw() != 1 || right.ww() != 1
    return 0
  if ffbc_verify_exact(left) != 1 || ffbc_verify_exact(right) != 1
    return 0

  capacity = left.rank() + right.rank() ## i64
  du = i64[capacity]
  dv = i64[capacity]
  dw = i64[capacity]
  owners = i64[capacity]
  count = ffnd_build_difference(left.us(), left.vs(), left.ws(), left.rank(), right.us(), right.vs(), right.ws(), right.rank(), du, dv, dw, owners) ## i64
  meta[0] = count
  if count < 2
    return 0

  combo_words = ffnd_combo_words(count) ## i64
  basis = i64[count * combo_words]
  elimination = i64[5]
  nullity = ffran_build_nullspace(du, dv, dw, count, left.n(), left.m(), left.p(), basis, elimination) ## i64
  meta[1] = nullity
  meta[2] = elimination[2]
  if nullity < 2 || nullity > max_nullity || nullity > 20
    return 0

  limit = 1 << nullity ## i64
  meta[3] = limit - 1
  relation = i64[combo_words]
  code = 1 ## i64
  added = 0 ## i64
  while code < limit && meta[4] < max_combinations && added < max_children
    z = ffnd_clear(relation, 0, combo_words)
    bit = 0 ## i64
    while bit < nullity
      if ((code >> bit) & 1) != 0
        z = ffnd_xor(basis, bit * combo_words, relation, 0, combo_words)
      bit += 1
    meta[4] += 1
    if ffran_relation_exact(du, dv, dw, count, left.n(), left.m(), left.p(), relation, 0) != 1
      meta[13] += 1
    else
      score = i64[3]
      projected = ffnd_score_mask(relation, 0, owners, count, left.rank(), score) ## i64
      if projected > 0
        meta[5] += 1
        child = ffran_materialize_relation(left, du, dv, dw, count, relation, projected)
        if child == nil
          meta[14] += 1
        else
          meta[6] += 1
          if ffbc_verify_exact(child) != 1
            meta[15] += 1
          else
            meta[7] += 1
            if meta[10] == 0 || child.rank() < meta[10]
              meta[10] = child.rank()
            if ffran_archive_find(archive, child) >= 0
              meta[9] += 1
            else
              archive.push(child)
              added += 1
              meta[8] = added

    code += 1
  if code < limit && meta[4] >= max_combinations
    meta[11] = 1
  if code < limit && added >= max_children
    meta[12] = 1
  added

# Breadth-first archive closure.  Pass zero audits all initial pairs; later
# passes audit only pairs touching a child from the preceding pass, so no pair
# is repeated.  Newly appended exact children become parents on the next pass.
# The pair primitive above provides the low-nullity/relation/child caps; this
# wrapper adds global pass, pair, and archive caps.
#
# meta:
#   0 initial archive, 1 final archive, 2 children added, 3 passes,
#   4 pairs audited, 5 productive pairs, 6 relations evaluated,
#   7 proper relations, 8 exact children, 9 duplicates,
#   10 minimum rank, 11 strict rank drops from initial minimum,
#   12 pairs skipped above max_nullity, 13 relation-capped pairs,
#   14 pair cap hit, 15 archive cap hit, 16 gate/materialization failures,
#   17 maximum observed nullity, 18 maximum difference size.
-> ffran_archive_closure(archive, max_passes, max_pairs, max_nullity, max_combinations, max_archive, meta) (Array i64 i64 i64 i64 i64 i64[]) i64
  if meta.size() < 19
    return 0
  z = ffnd_clear(meta, 0, 19) ## i64
  initial = archive.size() ## i64
  meta[0] = initial
  meta[1] = initial
  if initial < 2 || max_passes < 1 || max_pairs < 1 || max_nullity < 2 || max_nullity > 20 || max_combinations < 1 || max_archive <= initial
    return 0

  minimum_initial_rank = 0x7fffffff ## i64
  shape_n = archive[0].n() ## i64
  shape_m = archive[0].m() ## i64
  shape_p = archive[0].p() ## i64
  i = 0 ## i64
  while i < initial
    candidate = archive[i]
    if candidate == nil || candidate.n() != shape_n || candidate.m() != shape_m || candidate.p() != shape_p || ffbc_verify_exact(candidate) != 1
      return 0
    if candidate.rank() < minimum_initial_rank
      minimum_initial_rank = candidate.rank()
    i += 1
  meta[10] = minimum_initial_rank

  frontier_start = 0 ## i64
  frontier_end = initial ## i64
  pass = 0 ## i64
  while pass < max_passes && frontier_start < frontier_end && meta[4] < max_pairs && archive.size() < max_archive
    pair_end = archive.size() ## i64
    expected_pairs = pair_end * (pair_end - 1) / 2 ## i64
    if pass > 0
      expected_pairs -= frontier_start * (frontier_start - 1) / 2
    pairs_before = meta[4] ## i64
    i = 0
    while i < pair_end && meta[4] < max_pairs && archive.size() < max_archive
      j = i + 1 ## i64
      while j < pair_end && meta[4] < max_pairs && archive.size() < max_archive
        # On later passes only a pair touching the current frontier is new.
        if pass == 0 || i >= frontier_start || j >= frontier_start
          remaining = max_archive - archive.size() ## i64
          pair_meta = i64[16]
          before = archive.size() ## i64
          made = ffran_enumerate_children(archive[i], archive[j], max_nullity, max_combinations, remaining, archive, pair_meta) ## i64
          meta[4] += 1
          meta[6] += pair_meta[4]
          meta[7] += pair_meta[5]
          meta[8] += pair_meta[7]
          meta[9] += pair_meta[9]
          meta[16] += pair_meta[13] + pair_meta[14] + pair_meta[15]
          if pair_meta[1] > meta[17]
            meta[17] = pair_meta[1]
          if pair_meta[0] > meta[18]
            meta[18] = pair_meta[0]
          if pair_meta[1] > max_nullity
            meta[12] += 1
          if pair_meta[11] != 0
            meta[13] += 1
          if made > 0
            meta[5] += 1
            k = before ## i64
            while k < archive.size()
              rank = archive[k].rank() ## i64
              if rank < meta[10]
                meta[10] = rank
              if rank < minimum_initial_rank
                meta[11] += 1
              k += 1
          meta[2] += made
        j += 1
      i += 1
    audited_pairs = meta[4] - pairs_before ## i64
    if audited_pairs < expected_pairs
      if meta[4] >= max_pairs
        meta[14] = 1
      if archive.size() >= max_archive
        meta[15] = 1
    next_start = pair_end ## i64
    next_end = archive.size() ## i64
    frontier_start = next_start
    frontier_end = next_end
    pass += 1
    meta[3] = pass

  meta[1] = archive.size()
  meta[2]
