# Offline one-spectator repair for square k-XOR near misses.
#
# Let A be k selected live terms and B a proposed k-1 replacement.  A normal
# k-XOR join accepts only when E = xor(A) xor xor(B) is zero.  This strategy
# keeps a failed exact join and asks whether, for one unselected live spectator
# s, E xor s is either zero or one rank-one tensor q.  In the latter case
#
#     A + s = B + q
#
# is an exact (k+1)->k relation and therefore a net rank-one splice before
# parity collisions.  The zero case is an even larger drop.  Every result is
# materialized in a fresh worker state and exhaustively n^6-gated; the source
# state is never mutated.
#
# The bounded frontier screen at the bottom intentionally mirrors the mature
# 5->4 MITM candidate family.  It hashes every plausible projected `s xor q`
# repair pair, then probes four-term replacement residuals against that table.
# It is an offline decision experiment, not a production fleet lane.

use ../kernels/mitm

-> ffks_tensor_words(n) (i64) i64
  dim = n * n ## i64
  bits = dim * dim * dim ## i64
  (bits + 63) / 64

-> ffks_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffks_copy(source, target, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target[i] = source[i]
    i += 1
  count

-> ffks_tensor_bit(values, bit) (i64[] i64) i64
  (values[bit / 64] >> (bit % 64)) & 1

-> ffks_xor_outer(values, u, v, w, n) (i64[] i64 i64 i64 i64) i64
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
              bit = (ai * dim + bi) * dim + ci ## i64
              word = bit / 64 ## i64
              values[word] = values[word] ^ (1 << (bit % 64))
            ci += 1
        bi += 1
    ai += 1
  1

-> ffks_tensor_zero(values, words) (i64[] i64) i64
  i = 0 ## i64
  while i < words
    if values[i] != 0
      return 0
    i += 1
  1

# Recover the unique support-box factors of a nonzero binary rank-one tensor.
# A nonzero GF(2) outer product is exactly the indicator of U x V x W, so one
# pivot cell determines all three factor masks and a complete scan proves the
# factorization.  Return one only on proof; zero includes the all-zero tensor.
-> ffks_factor_rank_one(values, n, factors) (i64[] i64 i64[]) i64
  dim = n * n ## i64
  bits = dim * dim * dim ## i64
  pivot = 0 - 1 ## i64
  bit = 0 ## i64
  while bit < bits && pivot < 0
    if ffks_tensor_bit(values, bit) != 0
      pivot = bit
    bit += 1
  if pivot < 0
    return 0
  plane = dim * dim ## i64
  ai0 = pivot / plane ## i64
  rem = pivot - ai0 * plane ## i64
  bi0 = rem / dim ## i64
  ci0 = rem - bi0 * dim ## i64
  u = 0 ## i64
  v = 0 ## i64
  w = 0 ## i64
  ai = 0 ## i64
  while ai < dim
    if ffks_tensor_bit(values, (ai * dim + bi0) * dim + ci0) != 0
      u = u | (1 << ai)
    ai += 1
  bi = 0 ## i64
  while bi < dim
    if ffks_tensor_bit(values, (ai0 * dim + bi) * dim + ci0) != 0
      v = v | (1 << bi)
    bi += 1
  ci = 0 ## i64
  while ci < dim
    if ffks_tensor_bit(values, (ai0 * dim + bi0) * dim + ci) != 0
      w = w | (1 << ci)
    ci += 1
  ai = 0
  while ai < dim
    bi = 0
    while bi < dim
      ci = 0
      while ci < dim
        expected = ((u >> ai) & 1) & ((v >> bi) & 1) & ((w >> ci) & 1) ## i64
        if ffks_tensor_bit(values, (ai * dim + bi) * dim + ci) != expected
          return 0
        ci += 1
      bi += 1
    ai += 1
  factors[0] = u
  factors[1] = v
  factors[2] = w
  1

-> ffks_selected(selected, count, position) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == position
      return 1
    i += 1
  0

-> ffks_selected_valid(selected, count, rank) (i64[] i64 i64) i64
  if count < 1 || count >= rank
    return 0
  i = 0 ## i64
  while i < count
    if selected[i] < 0 || selected[i] >= rank
      return 0
    j = i + 1 ## i64
    while j < count
      if selected[i] == selected[j]
        return 0
      j += 1
    i += 1
  1

-> ffks_terms_valid(us, vs, ws, count, dim) (i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] <= 0 || vs[i] <= 0 || ws[i] <= 0
      return 0
    if (us[i] >> dim) != 0 || (vs[i] >> dim) != 0 || (ws[i] >> dim) != 0
      return 0
    i += 1
  1

-> ffks_build_residual(st, selected, selected_count, replacement_u, replacement_v, replacement_w, replacement_count, residual) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  n = st[2] ## i64
  rank = st[6] ## i64
  if ffks_selected_valid(selected, selected_count, rank) == 0
    return 0
  if replacement_count < 0 || replacement_count + 1 != selected_count
    return 0
  if ffks_terms_valid(replacement_u, replacement_v, replacement_w, replacement_count, n * n) == 0
    return 0
  words = ffks_tensor_words(n) ## i64
  z = ffks_clear(residual, words) ## i64
  i = 0 ## i64
  while i < selected_count
    slot = st[st[50] + selected[i]] ## i64
    z = ffks_xor_outer(residual, st[st[44] + slot], st[st[45] + slot], st[st[46] + slot], n)
    i += 1
  i = 0
  while i < replacement_count
    z = ffks_xor_outer(residual, replacement_u[i], replacement_v[i], replacement_w[i], n)
    i += 1
  1

# Toggle the proposed relation into plain exported term arrays, initialize a
# fresh state, and independently full-gate it.  Parity collisions are legal:
# they may make the actual drop larger than the nominal one, but never smaller.
-> ffks_materialize(st, selected, selected_count, spectator, replacement_u, replacement_v, replacement_w, replacement_count, repair_u, repair_v, repair_w, has_repair, out_state, capacity, seed) (i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64 i64) i64
  n = st[2] ## i64
  old_rank = st[6] ## i64
  if capacity < old_rank || spectator < 0 || spectator >= old_rank
    return 0
  if ffks_selected(selected, selected_count, spectator) != 0
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  rank = ffw_export_current(st, us, vs, ws) ## i64
  if rank != old_rank
    return 0
  source_u = i64[selected_count]
  source_v = i64[selected_count]
  source_w = i64[selected_count]
  i = 0 ## i64
  while i < selected_count
    slot = st[st[50] + selected[i]] ## i64
    source_u[i] = st[st[44] + slot]
    source_v[i] = st[st[45] + slot]
    source_w[i] = st[st[46] + slot]
    i += 1
  spectator_slot = st[st[50] + spectator] ## i64
  spectator_u = st[st[44] + spectator_slot] ## i64
  spectator_v = st[st[45] + spectator_slot] ## i64
  spectator_w = st[st[46] + spectator_slot] ## i64
  i = 0
  while i < selected_count && rank >= 0
    rank = ffm_toggle_plain(us, vs, ws, rank, capacity, source_u[i], source_v[i], source_w[i])
    i += 1
  if rank >= 0
    rank = ffm_toggle_plain(us, vs, ws, rank, capacity, spectator_u, spectator_v, spectator_w)
  i = 0
  while i < replacement_count && rank >= 0
    rank = ffm_toggle_plain(us, vs, ws, rank, capacity, replacement_u[i], replacement_v[i], replacement_w[i])
    i += 1
  if has_repair != 0 && rank >= 0
    rank = ffm_toggle_plain(us, vs, ws, rank, capacity, repair_u, repair_v, repair_w)
  if rank < 1 || rank >= old_rank
    return 0
  loaded = ffw_init_terms_cap(out_state, us, vs, ws, rank, n, capacity, seed, 0, 1, 1, 1) ## i64
  if loaded == rank && ffw_verify_current_exact(out_state, n) == 1 && ffw_verify_best_exact(out_state, n) == 1
    return rank
  0

# meta:
# [0] spectator tickets, [1] rank-one tests, [2] zero residuals,
# [3] rank-one residuals, [4] full gates, [5] accepted, [6] final rank,
# [7] spectator position, [8..10] repaired factor (zero for zero residual),
# [11] source rank.
-> ffks_try_repair(st, selected, selected_count, replacement_u, replacement_v, replacement_w, replacement_count, spectator_start, spectator_budget, out_state, capacity, seed, meta) (i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < 12
    meta[i] = 0
    i += 1
  if ffw_valid(st) == 0 || ffw_verify_current_exact(st, st[2]) == 0
    return 0
  rank = st[6] ## i64
  meta[11] = rank
  if spectator_budget < 1 || ffks_selected_valid(selected, selected_count, rank) == 0
    return 0
  words = ffks_tensor_words(st[2]) ## i64
  residual = i64[words]
  if ffks_build_residual(st, selected, selected_count, replacement_u, replacement_v, replacement_w, replacement_count, residual) == 0
    return 0
  # This lane is specifically for failed exact joins.  Exact replacements
  # belong to the ordinary k-XOR admission path.
  if ffks_tensor_zero(residual, words) != 0
    return 0
  budget = spectator_budget ## i64
  if budget > rank
    budget = rank
  start = spectator_start % rank ## i64
  if start < 0
    start += rank
  work = i64[words]
  factors = i64[3]
  ordinal = 0 ## i64
  while ordinal < budget
    spectator = (start + ordinal) % rank ## i64
    if ffks_selected(selected, selected_count, spectator) == 0
      meta[0] += 1
      z = ffks_copy(residual, work, words) ## i64
      slot = st[st[50] + spectator] ## i64
      z = ffks_xor_outer(work, st[st[44] + slot], st[st[45] + slot], st[st[46] + slot], st[2])
      is_zero = ffks_tensor_zero(work, words) ## i64
      has_repair = 0 ## i64
      repairable = is_zero ## i64
      if is_zero != 0
        meta[2] += 1
      if is_zero == 0
        meta[1] += 1
        if ffks_factor_rank_one(work, st[2], factors) != 0
          repairable = 1
          has_repair = 1
          meta[3] += 1
      if repairable != 0
        meta[4] += 1
        qu = 0 ## i64
        qv = 0 ## i64
        qw = 0 ## i64
        if has_repair != 0
          qu = factors[0]
          qv = factors[1]
          qw = factors[2]
        result = ffks_materialize(st, selected, selected_count, spectator, replacement_u, replacement_v, replacement_w, replacement_count, qu, qv, qw, has_repair, out_state, capacity, seed + spectator * 17) ## i64
        if result > 0
          meta[5] = 1
          meta[6] = result
          meta[7] = spectator
          meta[8] = qu
          meta[9] = qv
          meta[10] = qw
          return result
    ordinal += 1
  0

# Stable connectivity-biased five-term selector, equivalent in spirit to the
# production k-XOR selector but local to this offline strategy.
-> ffks_choose_five(us, vs, ws, rank, offset, selected) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if rank < 5
    return 0
  selected[0] = offset % rank
  count = 1 ## i64
  while count < 5
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    candidate = 0 ## i64
    while candidate < rank
      if ffks_selected(selected, count, candidate) == 0
        score = 0 ## i64
        i = 0 ## i64
        while i < count
          other = selected[i] ## i64
          if us[candidate] == us[other]
            score += 4
          if vs[candidate] == vs[other]
            score += 4
          if ws[candidate] == ws[other]
            score += 4
          score -= ffw_popcount(us[candidate] ^ us[other])
          score -= ffw_popcount(vs[candidate] ^ vs[other])
          score -= ffw_popcount(ws[candidate] ^ ws[other])
          i += 1
        if best < 0 || score > best_score
          best = candidate
          best_score = score
      candidate += 1
    if best < 0
      return 0
    selected[count] = best
    count += 1
  5

-> ffks_same_fp(a0, a1, a2, a3, b) (i64 i64 i64 i64 i64[]) i64
  if a0 == b[0] && a1 == b[1] && a2 == b[2] && a3 == b[3]
    return 1
  0

-> ffks_fp_hash(p0, p1, p2, p3, mask) (i64 i64 i64 i64 i64) i64
  # Fingerprint words are u32 values held in i64 slots.  This is only table
  # routing; all four complete words are compared before a ticket is issued.
  mixed = p0 ^ (p1 << 7) ^ (p1 >> 25) ^ (p2 << 13) ^ (p2 >> 19) ^ (p3 << 19) ^ (p3 >> 13) ## i64
  mixed = mixed ^ (mixed >> 16)
  mixed & mask

-> ffks_pair_insert(key0, key1, key2, key3, used, spectators, mask, p0, p1, p2, p3, spectator) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  slot = ffks_fp_hash(p0, p1, p2, p3, mask) ## i64
  scanned = 0 ## i64
  while used[slot] != 0 && scanned <= mask
    slot = (slot + 1) & mask
    scanned += 1
  if scanned > mask
    return 0
  key0[slot] = p0
  key1[slot] = p1
  key2[slot] = p2
  key3[slot] = p3
  spectators[slot] = spectator
  used[slot] = 1
  1

# Bounded square 5->4 spectator-projected screen.  For every unselected live
# spectator s and every rank-one term q in the bounded candidate pool, a hash
# table retains fp(s) xor fp(q).  A four-term replacement B is a repair ticket
# only when fp(A) xor fp(B) hits that table.  Only failed exact local joins are
# offered to the exact spectator repair.  Return the first fully gated drop.
# meta:
# [0] windows, [1] canonical replacement tuples, [2] projected pair hits,
# [3] already-exact joins, [4] near misses, [5] spectator tickets,
# [6] rank-one/zero repair candidates, [7] full gates, [8] accepted,
# [9] final rank, [10] pool sum, [11] source rank.
-> ffks_screen_frontier(source, windows, pool, nearby, offset, out_state, capacity, meta) (i64[] i64 i64 i64 i64 i64[] i64 i64[]) i64
  i = 0 ## i64
  while i < 12
    meta[i] = 0
    i += 1
  if ffw_valid(source) == 0 || ffw_verify_current_exact(source, source[2]) == 0
    return 0
  if windows < 1 || pool < 8 || pool > 96 || nearby < 0 || nearby > 8
    return 0
  rank = source[6] ## i64
  meta[11] = rank
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source, us, vs, ws) != rank
    return 0
  selected = i64[5]
  cu = i64[pool]
  cv = i64[pool]
  cw = i64[pool]
  fp0 = i64[pool]
  fp1 = i64[pool]
  fp2 = i64[pool]
  fp3 = i64[pool]
  live_fp0 = i64[rank]
  live_fp1 = i64[rank]
  live_fp2 = i64[rank]
  live_fp3 = i64[rank]
  words4 = i64[4]
  target = i64[4]
  replacement_u = i64[4]
  replacement_v = i64[4]
  replacement_w = i64[4]
  indices = i64[4]
  repair_meta = i64[12]
  i = 0
  while i < rank
    z = ffm_fingerprint(us[i], vs[i], ws[i], source[3], words4) ## i64
    live_fp0[i] = words4[0]
    live_fp1[i] = words4[1]
    live_fp2[i] = words4[2]
    live_fp3[i] = words4[3]
    i += 1
  table_cap = 1 ## i64
  while table_cap < rank * pool * 2
    table_cap *= 2
  table_mask = table_cap - 1 ## i64
  key0 = i64[table_cap]
  key1 = i64[table_cap]
  key2 = i64[table_cap]
  key3 = i64[table_cap]
  table_used = i64[table_cap]
  table_spectators = i64[table_cap]
  window = 0 ## i64
  while window < windows
    if ffks_choose_five(us, vs, ws, rank, offset + window * 17, selected) != 5
      return 0
    count = ffm_candidates(us, vs, ws, rank, selected, pool, nearby, cu, cv, cw) ## i64
    meta[0] += 1
    meta[10] += count
    i = 0
    while i < count
      z = ffm_fingerprint(cu[i], cv[i], cw[i], source[3], words4) ## i64
      fp0[i] = words4[0]
      fp1[i] = words4[1]
      fp2[i] = words4[2]
      fp3[i] = words4[3]
      i += 1
    z = ffm_target_fingerprint(us, vs, ws, selected, source[3], target)
    z = ffks_clear(table_used, table_cap)
    spectator = 0 ## i64
    while spectator < rank
      if ffks_selected(selected, 5, spectator) == 0
        q = 0 ## i64
        while q < count
          z = ffks_pair_insert(key0, key1, key2, key3, table_used, table_spectators, table_mask, live_fp0[spectator] ^ fp0[q], live_fp1[spectator] ^ fp1[q], live_fp2[spectator] ^ fp2[q], live_fp3[spectator] ^ fp3[q], spectator)
          q += 1
      spectator += 1
    a = 0 ## i64
    while a < count
      b = a + 1 ## i64
      while b < count
        c = b + 1 ## i64
        while c < count
          d = c + 1 ## i64
          while d < count
            meta[1] += 1
            residual0 = target[0] ^ fp0[a] ^ fp0[b] ^ fp0[c] ^ fp0[d] ## i64
            residual1 = target[1] ^ fp1[a] ^ fp1[b] ^ fp1[c] ^ fp1[d] ## i64
            residual2 = target[2] ^ fp2[a] ^ fp2[b] ^ fp2[c] ^ fp2[d] ## i64
            residual3 = target[3] ^ fp3[a] ^ fp3[b] ^ fp3[c] ^ fp3[d] ## i64
            table_slot = ffks_fp_hash(residual0, residual1, residual2, residual3, table_mask) ## i64
            table_scanned = 0 ## i64
            prepared = 0 ## i64
            exact_join = 0 ## i64
            while table_used[table_slot] != 0 && table_scanned < table_cap
              if key0[table_slot] == residual0 && key1[table_slot] == residual1 && key2[table_slot] == residual2 && key3[table_slot] == residual3
                meta[2] += 1
                if prepared == 0
                  indices[0] = a
                  indices[1] = b
                  indices[2] = c
                  indices[3] = d
                  exact_join = ffm_local_exact(us, vs, ws, selected, cu, cv, cw, indices, source[2]) ## i64
                  if exact_join != 0
                    meta[3] += 1
                  if exact_join == 0
                    meta[4] += 1
                    ri = 0 ## i64
                    while ri < 4
                      replacement_u[ri] = cu[indices[ri]]
                      replacement_v[ri] = cv[indices[ri]]
                      replacement_w[ri] = cw[indices[ri]]
                      ri += 1
                  prepared = 1
                if exact_join == 0
                  hit = ffks_try_repair(source, selected, 5, replacement_u, replacement_v, replacement_w, 4, table_spectators[table_slot], 1, out_state, capacity, 99001 + offset + window * 101, repair_meta) ## i64
                  meta[5] += repair_meta[0]
                  meta[6] += repair_meta[2] + repair_meta[3]
                  meta[7] += repair_meta[4]
                  if hit > 0
                    meta[8] = 1
                    meta[9] = hit
                    return hit
              table_slot = (table_slot + 1) & table_mask
              table_scanned += 1
            d += 1
          c += 1
        b += 1
      a += 1
    window += 1
  0
