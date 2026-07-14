# Exact span-complete local refactoring for FlipFleet.
#
# For k=3 or k=4 selected live terms, this module constructs independent
# GF(2) bases for the three factor spans, enumerates every nonzero factor in
# those spans, and assigns every resulting rank-one term an exact local tensor
# signature.  The signature needs at most k^3 bits: 27 bits for k=3 and all
# 64 bits of an i64 for k=4.  No probabilistic fingerprint is used.
#
# Public ABI (all caller-owned raw arrays have the stated minimum capacity):
#
#   ffsr_build_candidates(su,sv,sw,k,cu,cv,cw,sigs,original_ids,meta)
#     su/sv/sw:       k selected terms
#     cu/cv/cw/sigs:  capacity 3375 (343 is sufficient when k=3)
#     original_ids:   capacity 4
#     meta:           capacity 12; layout documented below
#     returns the number of complete span candidates, or 0 on invalid input.
#
#   ffsr_find_ids(sigs,count,target,original_ids,k,want,out_ids,meta)
#     complete exact search for the requested replacement cardinality.
#
#   ffsr_find_terms(su,sv,sw,k,want,out_u,out_v,out_w,meta)
#   ffsr_find_current(st,selected,k,want,out_u,out_v,out_w,meta)
#     return `want` on discovery and materialize the replacement factors.
#
#   ffsr_apply_current(st,selected,k,out_u,out_v,out_w,out_count)
#     reject zero/duplicate/no-op/global-collision replacements, splice the
#     current metaflip_worker state, and exhaustively verify all n^6 tensor
#     coefficients.  Failure rolls the current state back and returns -1.
#
# Requested move families are exactly 3->2, 3<->3, 3->4, 4->3, and 4<->4.
# Pair search is complete.  The worst k=4, 4-term search has 3375 candidates
# and 5,693,625 pairs; compact i32 chains bound its scratch memory near 63 MB.
#
# meta layout:
#   [0..2] independent U/V/W span dimensions
#   [3]    exact signature bits (<=27 or <=64)
#   [4]    candidate count
#   [5]    selected target signature (may be negative when bit 63 is set)
#   [6]    unordered candidate-pair count
#   [7]    hash-table bucket count used/planned by the last search
#   [8]    exact hash-chain entries/probes examined
#   [9]    original/permutation solutions rejected
#   [10]   requested replacement count
#   [11]   result count (zero when no replacement was found)

use metaflip_worker

-> ffsr_max_candidates(k) (i64) i64
  result = 0 ## i64
  if k == 3
    result = 343
  if k == 4
    result = 3375
  result

-> ffsr_move_supported(k, want) (i64 i64) i64
  ok = 0 ## i64
  if k == 3
    if want >= 2 && want <= 4
      ok = 1
  if k == 4
    if want == 3 || want == 4
      ok = 1
  ok

-> ffsr_clear_meta(meta) (i64[]) i64
  i = 0 ## i64
  while i < 12
    meta[i] = 0
    i += 1
  1

-> ffsr_contains(values, count, value) (i64[] i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if values[i] == value
      found = 1
      i = count
    else
      i += 1
  found

# Append `value` iff it is independent of the current (at most four-vector)
# basis.  Exhaustively enumerating the tiny existing span avoids pivot-state
# bookkeeping and is deterministic for every factor width up to 49 bits.
-> ffsr_basis_add(basis, count, value) (i64[] i64 i64) i64
  result = count ## i64
  if value != 0
    dependent = 0 ## i64
    combo = 0 ## i64
    limit = 1 << count ## i64
    while combo < limit
      made = 0 ## i64
      bit = 0 ## i64
      while bit < count
        if ((combo >> bit) & 1) != 0
          made = made ^ basis[bit]
        bit += 1
      if made == value
        dependent = 1
        combo = limit
      else
        combo += 1
    if dependent == 0
      basis[count] = value
      result = count + 1
  result

-> ffsr_make_basis(values, count, basis) (i64[] i64 i64[]) i64
  rank = 0 ## i64
  i = 0 ## i64
  valid = 1 ## i64
  while i < count
    if values[i] == 0
      valid = 0
    if values[i] != 0
      rank = ffsr_basis_add(basis, rank, values[i])
    i += 1
  if valid == 0
    rank = 0
  rank

# values[combo-1] is the actual ambient factor represented by nonzero basis
# coordinate mask `combo`.  Independence makes all outputs unique/nonzero.
-> ffsr_enumerate_span(basis, basis_count, values) (i64[] i64 i64[]) i64
  count = 0 ## i64
  if basis_count > 0
    combo = 1 ## i64
    limit = 1 << basis_count ## i64
    while combo < limit
      made = 0 ## i64
      bit = 0 ## i64
      while bit < basis_count
        if ((combo >> bit) & 1) != 0
          made = made ^ basis[bit]
        bit += 1
      values[count] = made
      count += 1
      combo += 1
  count

# Exact coordinate tensor for (u_coord) outer (v_coord) outer (w_coord).
# `one << 63` intentionally uses the sign bit when all three dimensions are 4.
-> ffsr_outer_signature(u_coord, v_coord, w_coord, rank_v, rank_w) (i64 i64 i64 i64 i64) i64
  signature = 0 ## i64
  one = 1 ## i64
  ui = 0 ## i64
  while (u_coord >> ui) != 0
    if ((u_coord >> ui) & 1) != 0
      vi = 0 ## i64
      while (v_coord >> vi) != 0
        if ((v_coord >> vi) & 1) != 0
          wi = 0 ## i64
          while (w_coord >> wi) != 0
            if ((w_coord >> wi) & 1) != 0
              position = (ui * rank_v + vi) * rank_w + wi ## i64
              signature = signature ^ (one << position)
            wi += 1
        vi += 1
    ui += 1
  signature

-> ffsr_find_candidate_term(cu, cv, cw, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < count
    if cu[i] == u && cv[i] == v && cw[i] == w
      found = i
      i = count
    else
      i += 1
  found

# This is deliberately public: a GPU wrapper can share the exact host basis,
# candidate ordering, target, and verification convention without duplicating
# any local algebra.
-> ffsr_build_candidates(su, sv, sw, k, cu, cv, cw, signatures, original_ids, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  z = ffsr_clear_meta(meta) ## i64
  result = 0 ## i64
  if k == 3 || k == 4
    ub = i64[4]
    vb = i64[4]
    wb = i64[4]
    ru = ffsr_make_basis(su, k, ub) ## i64
    rank_v = ffsr_make_basis(sv, k, vb) ## i64
    rank_w = ffsr_make_basis(sw, k, wb) ## i64
    meta[0] = ru
    meta[1] = rank_v
    meta[2] = rank_w
    meta[3] = ru * rank_v * rank_w
    if ru > 0 && rank_v > 0 && rank_w > 0
      uvalues = i64[15]
      vvalues = i64[15]
      wvalues = i64[15]
      nu = ffsr_enumerate_span(ub, ru, uvalues) ## i64
      nv = ffsr_enumerate_span(vb, rank_v, vvalues) ## i64
      nw = ffsr_enumerate_span(wb, rank_w, wvalues) ## i64
      count = 0 ## i64
      ui = 0 ## i64
      while ui < nu
        vi = 0 ## i64
        while vi < nv
          wi = 0 ## i64
          while wi < nw
            cu[count] = uvalues[ui]
            cv[count] = vvalues[vi]
            cw[count] = wvalues[wi]
            signatures[count] = ffsr_outer_signature(ui + 1, vi + 1, wi + 1, rank_v, rank_w)
            count += 1
            wi += 1
          vi += 1
        ui += 1
      meta[4] = count
      meta[6] = count * (count - 1) / 2
      valid = 1 ## i64
      target = 0 ## i64
      selected = 0 ## i64
      while selected < k
        id = ffsr_find_candidate_term(cu, cv, cw, count, su[selected], sv[selected], sw[selected]) ## i64
        if id < 0
          valid = 0
        if id >= 0
          if ffsr_contains(original_ids, selected, id) == 1
            valid = 0
          original_ids[selected] = id
          target = target ^ signatures[id]
        selected += 1
      if valid == 1
        meta[5] = target
        result = count
  result

-> ffsr_hash(signature, mask) (i64 i64) i64
  x = signature ^ (signature >> 21) ^ (signature >> 43) ## i64
  ((x * 6364136223846793005) ^ (x >> 17)) & mask

-> ffsr_single_table_capacity(count) (i64) i64
  capacity = 16 ## i64
  while capacity < count * 2
    capacity = capacity * 2
  capacity

-> ffsr_pair_table_capacity(count) (i64) i64
  pairs = count * (count - 1) / 2 ## i64
  wanted = (pairs + 1) / 2 ## i64
  capacity = 16 ## i64
  while capacity < wanted
    capacity = capacity * 2
  capacity

-> ffsr_build_single_table(signatures, count, table, mask) (i64[] i64 i32[] i64) i64
  i = 0 ## i64
  while i < count
    slot = ffsr_hash(signatures[i], mask) ## i64
    while table[slot] != 0
      slot = (slot + 1) & mask
    table[slot] = i + 1
    i += 1
  count

-> ffsr_lookup_signature(signatures, table, mask, wanted) (i64[] i32[] i64 i64) i64
  found = 0 - 1 ## i64
  slot = ffsr_hash(wanted, mask) ## i64
  while table[slot] != 0 && found < 0
    candidate = table[slot] - 1 ## i64
    if signatures[candidate] == wanted
      found = candidate
    if found < 0
      slot = (slot + 1) & mask
  found

-> ffsr_ids_distinct(ids, count) (i64[] i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    j = i + 1 ## i64
    while j < count
      if ids[i] == ids[j]
        ok = 0
      j += 1
    i += 1
  ok

-> ffsr_ids_same_set(left, left_count, right, right_count) (i64[] i64 i64[] i64) i64
  same = 0 ## i64
  if left_count == right_count
    same = 1
    i = 0 ## i64
    while i < left_count
      if ffsr_contains(right, right_count, left[i]) == 0
        same = 0
      i += 1
  same

-> ffsr_accept_ids(ids, count, original_ids, k) (i64[] i64 i64[] i64) i64
  ok = ffsr_ids_distinct(ids, count) ## i64
  if ok == 1
    if count == k
      if ffsr_ids_same_set(ids, count, original_ids, k) == 1
        ok = 0
  ok

-> ffsr_find_two_ids(signatures, count, target, original_ids, k, out_ids, meta) (i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  found = 0 ## i64
  left = 0 ## i64
  while left < count && found == 0
    right = left + 1 ## i64
    while right < count && found == 0
      meta[8] = meta[8] + 1
      if (signatures[left] ^ signatures[right]) == target
        out_ids[0] = left
        out_ids[1] = right
        if ffsr_accept_ids(out_ids, 2, original_ids, k) == 1
          found = 2
      right += 1
    left += 1
  found

-> ffsr_find_three_ids(signatures, count, target, original_ids, k, out_ids, meta) (i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  found = 0 ## i64
  capacity = ffsr_single_table_capacity(count) ## i64
  meta[7] = capacity
  table = i32[capacity]
  z = ffsr_build_single_table(signatures, count, table, capacity - 1) ## i64
  left = 0 ## i64
  while left < count && found == 0
    right = left + 1 ## i64
    while right < count && found == 0
      meta[8] = meta[8] + 1
      wanted = target ^ signatures[left] ^ signatures[right] ## i64
      third = ffsr_lookup_signature(signatures, table, capacity - 1, wanted) ## i64
      if third >= 0
        if third != left && third != right
          out_ids[0] = left
          out_ids[1] = right
          out_ids[2] = third
          if ffsr_accept_ids(out_ids, 3, original_ids, k) == 1
            found = 3
          else
            meta[9] = meta[9] + 1
      right += 1
    left += 1
  found

# Complete pair/pair MITM.  Each pair is queried against all earlier pairs,
# then inserted.  packed = left*count+right fits safely in i32 at count<=3375.
-> ffsr_find_four_ids(signatures, count, target, original_ids, k, out_ids, meta) (i64[] i64 i64 i64[] i64 i64[] i64[]) i64
  found = 0 ## i64
  pair_count = count * (count - 1) / 2 ## i64
  capacity = ffsr_pair_table_capacity(count) ## i64
  meta[6] = pair_count
  meta[7] = capacity
  heads = i32[capacity]
  nexts = i32[pair_count]
  packed_pairs = i32[pair_count]
  pair_id = 0 ## i64
  left = 0 ## i64
  while left < count && found == 0
    right = left + 1 ## i64
    while right < count && found == 0
      pair_signature = signatures[left] ^ signatures[right] ## i64
      wanted = target ^ pair_signature ## i64
      bucket = ffsr_hash(wanted, capacity - 1) ## i64
      link = heads[bucket] ## i64
      while link != 0 && found == 0
        other_id = link - 1 ## i64
        packed = packed_pairs[other_id] ## i64
        other_left = packed / count ## i64
        other_right = packed - other_left * count ## i64
        meta[8] = meta[8] + 1
        if (signatures[other_left] ^ signatures[other_right]) == wanted
          if other_left != left && other_left != right
            if other_right != left && other_right != right
              out_ids[0] = other_left
              out_ids[1] = other_right
              out_ids[2] = left
              out_ids[3] = right
              if ffsr_accept_ids(out_ids, 4, original_ids, k) == 1
                found = 4
              else
                meta[9] = meta[9] + 1
        link = nexts[other_id]
      insert_bucket = ffsr_hash(pair_signature, capacity - 1) ## i64
      packed_pairs[pair_id] = left * count + right
      nexts[pair_id] = heads[insert_bucket]
      heads[insert_bucket] = pair_id + 1
      pair_id += 1
      right += 1
    left += 1
  found

# Public exact host search over an already-built candidate/signature set.
-> ffsr_find_ids(signatures, count, target, original_ids, k, want, out_ids, meta) (i64[] i64 i64 i64[] i64 i64 i64[] i64[]) i64
  result = 0 ## i64
  meta[7] = 0
  meta[8] = 0
  meta[9] = 0
  meta[10] = want
  meta[11] = 0
  if ffsr_move_supported(k, want) == 1
    if count > 0 && count <= ffsr_max_candidates(k)
      if want == 2
        result = ffsr_find_two_ids(signatures, count, target, original_ids, k, out_ids, meta)
      if want == 3
        result = ffsr_find_three_ids(signatures, count, target, original_ids, k, out_ids, meta)
      if want == 4
        result = ffsr_find_four_ids(signatures, count, target, original_ids, k, out_ids, meta)
  meta[11] = result
  result

-> ffsr_materialize_ids(cu, cv, cw, candidate_count, ids, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[]) i64
  result = 0 ## i64
  if ffsr_ids_distinct(ids, count) == 1
    valid = 1 ## i64
    i = 0 ## i64
    while i < count
      if ids[i] < 0 || ids[i] >= candidate_count
        valid = 0
      if valid == 1
        out_u[i] = cu[ids[i]]
        out_v[i] = cv[ids[i]]
        out_w[i] = cw[ids[i]]
      i += 1
    if valid == 1
      result = count
  result

-> ffsr_find_terms(su, sv, sw, k, want, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if ffsr_move_supported(k, want) == 1
    capacity = ffsr_max_candidates(k) ## i64
    cu = i64[capacity]
    cv = i64[capacity]
    cw = i64[capacity]
    signatures = i64[capacity]
    original_ids = i64[4]
    out_ids = i64[4]
    count = ffsr_build_candidates(su, sv, sw, k, cu, cv, cw, signatures, original_ids, meta) ## i64
    if count > 0
      found = ffsr_find_ids(signatures, count, meta[5], original_ids, k, want, out_ids, meta) ## i64
      if found == want
        result = ffsr_materialize_ids(cu, cv, cw, count, out_ids, found, out_u, out_v, out_w)
  result

-> ffsr_selected_positions_valid(selected, k, rank) (i64[] i64 i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < k
    if selected[i] < 0 || selected[i] >= rank
      ok = 0
    j = i + 1 ## i64
    while j < k
      if selected[i] == selected[j]
        ok = 0
      j += 1
    i += 1
  ok

-> ffsr_capture_current(st, selected, k, su, sv, sw) (i64[] i64[] i64 i64[] i64[] i64[]) i64
  ok = ffsr_selected_positions_valid(selected, k, st[6]) ## i64
  if ok == 1
    i = 0 ## i64
    while i < k
      slot = st[st[50] + selected[i]] ## i64
      su[i] = st[st[44] + slot]
      sv[i] = st[st[45] + slot]
      sw[i] = st[st[46] + slot]
      i += 1
  ok

-> ffsr_find_current(st, selected, k, want, out_u, out_v, out_w, meta) (i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  result = 0 ## i64
  if ffw_valid(st) == 1
    su = i64[4]
    sv = i64[4]
    sw = i64[4]
    if ffsr_capture_current(st, selected, k, su, sv, sw) == 1
      result = ffsr_find_terms(su, sv, sw, k, want, out_u, out_v, out_w, meta)
  result

-> ffsr_same_term(u1, v1, w1, u2, v2, w2) (i64 i64 i64 i64 i64 i64) i64
  same = 0 ## i64
  if u1 == u2 && v1 == v2 && w1 == w2
    same = 1
  same

-> ffsr_terms_same_set(lu, lv, lw, lcount, ru, rv, right_w, rcount) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  same = 0 ## i64
  if lcount == rcount
    same = 1
    i = 0 ## i64
    while i < lcount
      found = 0 ## i64
      j = 0 ## i64
      while j < rcount
        if ffsr_same_term(lu[i], lv[i], lw[i], ru[j], rv[j], right_w[j]) == 1
          found = 1
        j += 1
      if found == 0
        same = 0
      i += 1
  same

-> ffsr_output_well_formed(out_u, out_v, out_w, count) (i64[] i64[] i64[] i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    if out_u[i] == 0 || out_v[i] == 0 || out_w[i] == 0
      ok = 0
    j = i + 1 ## i64
    while j < count
      if ffsr_same_term(out_u[i], out_v[i], out_w[i], out_u[j], out_v[j], out_w[j]) == 1
        ok = 0
      j += 1
    i += 1
  ok

-> ffsr_position_selected(selected, k, position) (i64[] i64 i64) i64
  ffsr_contains(selected, k, position)

# Direct exact splice into the current worker view.  The function performs a
# precondition exact gate, validates set semantics, mutates via ffw_toggle,
# and performs the exhaustive postcondition gate.  Any failure restores the
# original current term set before returning -1.
-> ffsr_apply_current(st, selected, k, out_u, out_v, out_w, out_count) (i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  result = 0 - 1 ## i64
  if ffw_valid(st) == 1
    old_rank = st[6] ## i64
    expected = old_rank - k + out_count ## i64
    valid = ffsr_move_supported(k, out_count) ## i64
    if valid == 1
      if expected < 1 || expected > st[4]
        valid = 0
    if valid == 1
      if ffsr_selected_positions_valid(selected, k, old_rank) == 0
        valid = 0
    if valid == 1
      if ffsr_output_well_formed(out_u, out_v, out_w, out_count) == 0
        valid = 0
    su = i64[4]
    sv = i64[4]
    sw = i64[4]
    if valid == 1
      valid = ffsr_capture_current(st, selected, k, su, sv, sw)
    if valid == 1
      if ffsr_terms_same_set(su, sv, sw, k, out_u, out_v, out_w, out_count) == 1
        valid = 0
    # A replacement equal to an unselected live term would cancel it under
    # the worker's XOR-set representation rather than produce a legal splice.
    if valid == 1
      position = 0 ## i64
      while position < old_rank
        if ffsr_position_selected(selected, k, position) == 0
          slot = st[st[50] + position] ## i64
          live_u = st[st[44] + slot] ## i64
          live_v = st[st[45] + slot] ## i64
          live_w = st[st[46] + slot] ## i64
          oi = 0 ## i64
          while oi < out_count
            if ffsr_same_term(live_u, live_v, live_w, out_u[oi], out_v[oi], out_w[oi]) == 1
              valid = 0
            oi += 1
        position += 1
    if valid == 1
      if ffw_verify_current_exact(st, st[2]) == 0
        valid = 0
    if valid == 1
      rank = old_rank ## i64
      i = 0 ## i64
      while i < k
        rank = ffw_toggle(st, su[i], sv[i], sw[i], rank)
        i += 1
      i = 0
      while i < out_count
        rank = ffw_toggle(st, out_u[i], out_v[i], out_w[i], rank)
        i += 1
      st[6] = rank
      if rank == expected
        if ffw_verify_current_exact(st, st[2]) == 1
          result = rank
      if result < 0
        # All collision/capacity conditions were checked before mutation, so
        # toggling the replacement and original sets again is an exact undo.
        i = 0
        while i < out_count
          rank = ffw_toggle(st, out_u[i], out_v[i], out_w[i], rank)
          i += 1
        i = 0
        while i < k
          rank = ffw_toggle(st, su[i], sv[i], sw[i], rank)
          i += 1
        st[6] = rank
        z = ffw_verify_current_exact(st, st[2])
  result

# Standalone exact checker for tests and GPU admission: rebuild the selected
# span, map each replacement to that complete candidate set, and compare the
# exact local signatures.
-> ffsr_verify_local_replacement(su, sv, sw, k, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  ok = 0 ## i64
  if k == 3 || k == 4
    capacity = ffsr_max_candidates(k) ## i64
    cu = i64[capacity]
    cv = i64[capacity]
    cw = i64[capacity]
    signatures = i64[capacity]
    originals = i64[4]
    meta = i64[12]
    count = ffsr_build_candidates(su, sv, sw, k, cu, cv, cw, signatures, originals, meta) ## i64
    if count > 0 && ffsr_output_well_formed(out_u, out_v, out_w, out_count) == 1
      got = 0 ## i64
      valid = 1 ## i64
      i = 0 ## i64
      while i < out_count
        id = ffsr_find_candidate_term(cu, cv, cw, count, out_u[i], out_v[i], out_w[i]) ## i64
        if id < 0
          valid = 0
        if id >= 0
          got = got ^ signatures[id]
        i += 1
      if valid == 1 && got == meta[5]
        ok = 1
  ok
