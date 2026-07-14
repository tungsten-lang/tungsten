# Exact archive-difference nullspace crossover for FlipFleet.
#
# For two decompositions A and B of the same tensor, D=A symmetric-difference B
# is a tensor-zero set.  This module expands every term of D into its complete
# n^6-bit column, performs bit-packed GF(2) column elimination while tracking
# provenance, and returns a basis for ker(D).  Bounded combinations of those
# basis vectors are scored as toggles into A.  A selected proper relation gives
# an exact hybrid distinct from both archive parents.
#
# There are no probabilistic fingerprints.  `ffnd_crossover_states` exact-gates
# both parents and initializes/verifies the materialized child in a fresh worker
# state before returning it to the caller.

use metaflip_worker

-> ffnd_tensor_words(n) (i64) i64
  bits = n * n * n * n * n * n ## i64
  (bits + 63) / 64

-> ffnd_combo_words(count) (i64) i64
  (count + 63) / 64

-> ffnd_clear(words, offset, count) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    words[offset + i] = 0
    i += 1
  count

-> ffnd_copy(source, source_offset, target, target_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target[target_offset + i] = source[source_offset + i]
    i += 1
  count

-> ffnd_xor(source, source_offset, target, target_offset, count) (i64[] i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    target[target_offset + i] = target[target_offset + i] ^ source[source_offset + i]
    i += 1
  count

-> ffnd_xor_outer(words, offset, u, v, w, n) (i64[] i64 i64 i64 i64 i64) i64
  dim = n * n ## i64
  ai = 0 ## i64
  while ai < dim
    if ((u >> ai) & 1) != 0
      bi = 0 ## i64
      while bi < dim
        if ((v >> bi) & 1) != 0
          ci = 0 ## i64
          while ci < dim
            if ((w >> ci) & 1) != 0
              tensor_bit = (ai * dim + bi) * dim + ci ## i64
              word = tensor_bit / 64 ## i64
              shift = tensor_bit % 64 ## i64
              words[offset + word] = words[offset + word] ^ (1 << shift)
            ci += 1
        bi += 1
    ai += 1
  1

-> ffnd_first_set(words, offset, count) (i64[] i64 i64) i64
  result = 0 - 1 ## i64
  word = 0 ## i64
  while word < count && result < 0
    value = words[offset + word] ## i64
    if value != 0
      bit = 0 ## i64
      while bit < 64 && result < 0
        if ((value >> bit) & 1) != 0
          result = word * 64 + bit
        bit += 1
    word += 1
  result

-> ffnd_mask_bit(words, offset, bit) (i64[] i64 i64) i64
  (words[offset + bit / 64] >> (bit % 64)) & 1

-> ffnd_set_mask_bit(words, offset, bit) (i64[] i64 i64) i64
  word = offset + bit / 64 ## i64
  words[word] = words[word] | (1 << (bit % 64))
  1

-> ffnd_same_term(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u0 == u1 && v0 == v1 && w0 == w1
    same = 1
  same

-> ffnd_term_in(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < rank && found == 0
    if ffnd_same_term(us[i], vs[i], ws[i], u, v, w) == 1
      found = 1
    i += 1
  found

# owners[i]=0 for A-exclusive terms and 1 for B-exclusive terms.
-> ffnd_build_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, owners) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < arank
    if ffnd_term_in(bu, bv, bw, brank, au[i], av[i], aw[i]) == 0
      du[count] = au[i]
      dv[count] = av[i]
      dw[count] = aw[i]
      owners[count] = 0
      count += 1
    i += 1
  i = 0
  while i < brank
    if ffnd_term_in(au, av, aw, arank, bu[i], bv[i], bw[i]) == 0
      du[count] = bu[i]
      dv[count] = bv[i]
      dw[count] = bw[i]
      owners[count] = 1
      count += 1
    i += 1
  count

# out_basis stores nullity rows, each ceil(count/64) words.  meta layout:
# [0] tensor words, [1] combination words, [2] exact column rank,
# [3] nullity, [4] row-XOR reductions.
-> ffnd_build_nullspace(us, vs, ws, count, n, out_basis, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  if count < 1 || n < 2 || n > 7
    return 0
  tensor_bits = n * n * n * n * n * n ## i64
  tensor_words = ffnd_tensor_words(n) ## i64
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
    z = ffnd_xor_outer(work_tensor, 0, us[column], vs[column], ws[column], n)
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

-> ffnd_relation_exact(us, vs, ws, count, n, mask, mask_offset) (i64[] i64[] i64[] i64 i64 i64[] i64) i64
  words = ffnd_tensor_words(n) ## i64
  tensor = i64[words]
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, mask_offset, i) != 0
      z = ffnd_xor_outer(tensor, 0, us[i], vs[i], ws[i], n) ## i64
    i += 1
  exact = 1 ## i64
  i = 0
  while i < words && exact == 1
    if tensor[i] != 0
      exact = 0
    i += 1
  exact

-> ffnd_score_mask(mask, offset, owners, count, arank, stats) (i64[] i64 i64[] i64 i64 i64[]) i64
  selected = 0 ## i64
  from_a = 0 ## i64
  from_b = 0 ## i64
  i = 0 ## i64
  while i < count
    if ffnd_mask_bit(mask, offset, i) != 0
      selected += 1
      if owners[i] == 0
        from_a += 1
      if owners[i] == 1
        from_b += 1
    i += 1
  stats[0] = selected
  stats[1] = from_a
  stats[2] = from_b
  if selected == 0 || selected == count
    return 0 - 1
  arank - from_a + from_b

-> ffnd_consider_mask(candidate, combo_words, owners, count, arank, best_mask, best) (i64[] i64 i64[] i64 i64 i64[] i64[]) i64
  stats = i64[3]
  projected = ffnd_score_mask(candidate, 0, owners, count, arank, stats) ## i64
  improved = 0 ## i64
  if projected > 0
    if best[0] < 0 || projected < best[0]
      improved = 1
    if projected == best[0] && stats[0] > best[1]
      improved = 1
  if improved == 1
    z = ffnd_copy(candidate, 0, best_mask, 0, combo_words) ## i64
    best[0] = projected
    best[1] = stats[0]
    best[2] = stats[1]
    best[3] = stats[2]
  improved

# Enumerate singles, pairs, triples, then (for small nullity) the remaining
# binary combinations until max_combinations is exhausted.  This gives every
# basis direction a chance before spending the budget on deeper combinations.
# meta: [0] evaluated, [1] projected rank, [2] selected distance,
# [3] A removals, [4] B additions, [5] nullity.
-> ffnd_select_hybrid(basis, nullity, count, owners, arank, max_combinations, out_mask, meta) (i64[] i64 i64 i64[] i64 i64 i64[] i64[]) i64
  if nullity < 1 || count < 2 || max_combinations < 1
    return 0
  combo_words = ffnd_combo_words(count) ## i64
  candidate = i64[combo_words]
  best = i64[4]
  best[0] = 0 - 1
  evaluated = 0 ## i64

  i = 0 ## i64
  while i < nullity && evaluated < max_combinations
    z = ffnd_clear(candidate, 0, combo_words) ## i64
    z = ffnd_xor(basis, i * combo_words, candidate, 0, combo_words)
    z = ffnd_consider_mask(candidate, combo_words, owners, count, arank, out_mask, best)
    evaluated += 1
    i += 1

  i = 0
  while i < nullity && evaluated < max_combinations
    j = i + 1 ## i64
    while j < nullity && evaluated < max_combinations
      z = ffnd_clear(candidate, 0, combo_words)
      z = ffnd_xor(basis, i * combo_words, candidate, 0, combo_words)
      z = ffnd_xor(basis, j * combo_words, candidate, 0, combo_words)
      z = ffnd_consider_mask(candidate, combo_words, owners, count, arank, out_mask, best)
      evaluated += 1
      j += 1
    i += 1

  i = 0
  while i < nullity && evaluated < max_combinations
    j = i + 1 ## i64
    while j < nullity && evaluated < max_combinations
      k = j + 1 ## i64
      while k < nullity && evaluated < max_combinations
        z = ffnd_clear(candidate, 0, combo_words)
        z = ffnd_xor(basis, i * combo_words, candidate, 0, combo_words)
        z = ffnd_xor(basis, j * combo_words, candidate, 0, combo_words)
        z = ffnd_xor(basis, k * combo_words, candidate, 0, combo_words)
        z = ffnd_consider_mask(candidate, combo_words, owners, count, arank, out_mask, best)
        evaluated += 1
        k += 1
      j += 1
    i += 1

  # Dense combinations matter when primitive nullspace directions overlap.
  # Restrict binary enumeration to 20 basis vectors so shifts stay bounded.
  if nullity <= 20
    code = 1 ## i64
    limit = 1 << nullity ## i64
    while code < limit && evaluated < max_combinations
      z = ffnd_clear(candidate, 0, combo_words)
      bit = 0 ## i64
      while bit < nullity
        if ((code >> bit) & 1) != 0
          z = ffnd_xor(basis, bit * combo_words, candidate, 0, combo_words)
        bit += 1
      z = ffnd_consider_mask(candidate, combo_words, owners, count, arank, out_mask, best)
      evaluated += 1
      code += 1

  meta[0] = evaluated
  meta[1] = best[0]
  meta[2] = best[1]
  meta[3] = best[2]
  meta[4] = best[3]
  meta[5] = nullity
  if best[0] > 0
    return best[0]
  0

-> ffnd_toggle_plain(us, vs, ws, rank, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank && found < 0
    if ffnd_same_term(us[i], vs[i], ws[i], u, v, w) == 1
      found = i
    i += 1
  if found >= 0
    us[found] = us[rank - 1]
    vs[found] = vs[rank - 1]
    ws[found] = ws[rank - 1]
    return rank - 1
  if rank >= capacity
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffnd_materialize(au, av, aw, arank, du, dv, dw, count, relation, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  capacity = out_u.size() ## i64
  if out_v.size() < capacity
    capacity = out_v.size()
  if out_w.size() < capacity
    capacity = out_w.size()
  if arank > capacity
    return 0 - 1
  i = 0 ## i64
  while i < arank
    out_u[i] = au[i]
    out_v[i] = av[i]
    out_w[i] = aw[i]
    i += 1
  rank = arank ## i64
  i = 0
  while i < count && rank >= 0
    if ffnd_mask_bit(relation, 0, i) != 0
      rank = ffnd_toggle_plain(out_u, out_v, out_w, rank, capacity, du[i], dv[i], dw[i])
    i += 1
  rank

# End-to-end current-state crossover.  meta layout:
# [0] difference, [1] nullity, [2] column rank, [3] combinations evaluated,
# [4] child rank, [5] selected terms, [6] A removals, [7] B additions,
# [8] independent exact child gate.
-> ffnd_crossover_states(parent_a, parent_b, n, max_difference, max_combinations, out_u, out_v, out_w, meta) (i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if ffw_valid(parent_a) != 1 || ffw_valid(parent_b) != 1
    return 0
  if parent_a[2] != n || parent_b[2] != n
    return 0
  if ffw_verify_current_exact(parent_a, n) != 1 || ffw_verify_current_exact(parent_b, n) != 1
    return 0
  arank = parent_a[6] ## i64
  brank = parent_b[6] ## i64
  acap = parent_a[4] ## i64
  bcap = parent_b[4] ## i64
  au = i64[acap]
  av = i64[acap]
  aw = i64[acap]
  bu = i64[bcap]
  bv = i64[bcap]
  bw = i64[bcap]
  z = ffw_export_current(parent_a, au, av, aw) ## i64
  z = ffw_export_current(parent_b, bu, bv, bw)
  diff_capacity = arank + brank ## i64
  du = i64[diff_capacity]
  dv = i64[diff_capacity]
  dw = i64[diff_capacity]
  owners = i64[diff_capacity]
  count = ffnd_build_difference(au, av, aw, arank, bu, bv, bw, brank, du, dv, dw, owners) ## i64
  meta[0] = count
  if count < 2 || count > max_difference
    return 0
  combo_words = ffnd_combo_words(count) ## i64
  basis = i64[count * combo_words]
  elimination = i64[5]
  nullity = ffnd_build_nullspace(du, dv, dw, count, n, basis, elimination) ## i64
  meta[1] = nullity
  meta[2] = elimination[2]
  if nullity < 2
    return 0
  relation = i64[combo_words]
  selection = i64[6]
  projected = ffnd_select_hybrid(basis, nullity, count, owners, arank, max_combinations, relation, selection) ## i64
  meta[3] = selection[0]
  meta[4] = projected
  meta[5] = selection[2]
  meta[6] = selection[3]
  meta[7] = selection[4]
  if projected < 1
    return 0
  if ffnd_relation_exact(du, dv, dw, count, n, relation, 0) != 1
    return 0
  child_rank = ffnd_materialize(au, av, aw, arank, du, dv, dw, count, relation, out_u, out_v, out_w) ## i64
  if child_rank != projected
    return 0
  child_capacity = out_u.size() ## i64
  if child_capacity < child_rank
    return 0
  scratch = i64[ffw_state_size(child_capacity)]
  loaded = ffw_init_terms_cap(scratch, out_u, out_v, out_w, child_rank, n, child_capacity, 97001 + count, 0, 1, 1, 1) ## i64
  if loaded == child_rank && ffw_verify_current_exact(scratch, n) == 1
    meta[8] = 1
    return child_rank
  0
