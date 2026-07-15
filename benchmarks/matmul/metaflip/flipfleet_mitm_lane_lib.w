# Pure-Tungsten bounded GPU meet-in-the-middle lane for FlipFleet.
#
# The lane searches exact 5 -> 4 local surgeries.  It deliberately keeps the
# search family finite: factors from the five selected terms, pairwise factor
# XORs, and a bounded number of nearby factors from the exact input scheme.
# Metal performs both regular quadratic phases; the Tungsten host builds the
# collision-preserving table, reconstructs fingerprint hits, and admits an
# output only after exhaustive n^6 verification of the complete spliced
# scheme.  The runtime contains no Python process or Python-generated request.
#
# Public entry points:
#   ffm_search(seed,out,n,subsets,pool,nearby,offset,metal_path)
#   ffm_search_exact_subset(seed,out,n,pool,nearby,subset,metal_path)
#   ffm_plan_valid / ffm_plan_threads
#
# Compile an importing executable with @gpu support and pass that executable's
# sibling .metal path to ffm_search.  The checked-in flipfleet_mitm_lane.w is a
# ready-to-run CLI wrapper; flipfleet_native can import this module and pass
# benchmarks/matmul/metaflip/flipfleet_native.metal.  Repeated fleet epochs
# should normally use ffm_build/ffm_epoch_command: the current Metal bridge
# releases its retained buffer handles at child-process exit.

## u32[]: fps0, fps1, fps2, fps3, pair0, pair1, pair2, pair3
## i32[]: enum_params
@gpu fn ffm_enumerate_pairs(fps0, fps1, fps2, fps3, pair0, pair1, pair2, pair3, enum_params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = enum_params[0] ## i32
  left = tid / count ## i32
  right = tid - left * count ## i32
  if left < right
    pair0[tid] = fps0[left] ^ fps0[right]
    pair1[tid] = fps1[left] ^ fps1[right]
    pair2[tid] = fps2[left] ^ fps2[right]
    pair3[tid] = fps3[left] ^ fps3[right]

## u32[]: q0, q1, q2, q3, table0, table1, table2, table3, table_used, table_pair, target_fp, matches
## i32[]: probe_params
@gpu fn ffm_probe_pairs(q0, q1, q2, q3, table0, table1, table2, table3, table_used, table_pair, target_fp, matches, probe_params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = probe_params[0] ## i32
  table_mask = probe_params[1] ## u32
  table_cap = probe_params[2] ## i32
  left = tid / count ## i32
  right = tid - left * count ## i32
  outbase = tid * 16 ## i32
  hit = 0 ## i32
  while hit < 16
    matches[outbase + hit] = 0
    hit = hit + 1
  if left < right
    want0 = target_fp[0] ^ q0[left] ^ q0[right] ## u32
    want1 = target_fp[1] ^ q1[left] ^ q1[right] ## u32
    want2 = target_fp[2] ^ q2[left] ^ q2[right] ## u32
    want3 = target_fp[3] ^ q3[left] ^ q3[right] ## u32
    # Mix all 128 projected bits. The previous shift-only hash discarded the
    # low bits of three words and formed long structured clusters on the small
    # rectangular tensors, leaving the CPU table builder as the bottleneck.
    mixed = want0 ^ (want1 << 7) ^ (want1 >> 25) ^ (want2 << 13) ^ (want2 >> 19) ^ (want3 << 19) ^ (want3 >> 13) ## u32
    mixed = (mixed ^ (mixed >> 16)) * 73244475
    mixed = (mixed ^ (mixed >> 16)) * 73244475
    mixed = mixed ^ (mixed >> 16)
    slot_u = mixed & table_mask ## u32
    slot = slot_u ## i32
    scanned = 0 ## i32
    found = 0 ## i32
    while scanned < table_cap
      if table_used[slot] == 0
        scanned = table_cap
      else
        if table0[slot] == want0
          if table1[slot] == want1
            if table2[slot] == want2
              if table3[slot] == want3
                packed_u = table_pair[slot] ## u32
                packed = packed_u ## i32
                other_left = packed / count ## i32
                other_right = packed - other_left * count ## i32
                if other_left != left
                  if other_left != right
                    if other_right != left
                      if other_right != right
                        if found < 16
                          matches[outbase + found] = packed_u
                          found = found + 1
        slot = (slot + 1) & table_mask
        scanned = scanned + 1

use core/metal
use metaflip_worker
use flipfleet_gpu_worker_bundle

-> ffm_plan_valid(n, subsets, pool, nearby, offset) (i64 i64 i64 i64 i64) i64
  ok = 1 ## i64
  if n < 3 || n > 7
    ok = 0
  if subsets < 1 || subsets > 16
    ok = 0
  if pool < 4 || pool > 700
    ok = 0
  if nearby < 0 || nearby > 8
    ok = 0
  if offset < 0
    ok = 0
  ok

-> ffm_plan_threads(subsets, pool) (i64 i64) i64
  subsets * pool * pool

-> ffm_contains(values, count, value) (i64[] i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if values[i] == value
      found = 1
      i = count
    else
      i += 1
  found

-> ffm_add_unique(values, count, cap, value) (i64[] i64 i64 i64) i64
  result = count ## i64
  if value != 0
    if ffm_contains(values, count, value) == 0
      if count < cap
        values[count] = value
        result = count + 1
  result

-> ffm_axis_value(us, vs, ws, index, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[index] ## i64
  if axis == 1
    value = vs[index]
  if axis == 2
    value = ws[index]
  value

-> ffm_selected_index(selected, count, index) (i64[] i64 i64) i64
  ffm_contains(selected, count, index)

-> ffm_min_axis_distance(value, selected_values, selected_count) (i64 i64[] i64) i64
  best = 999999999 ## i64
  i = 0 ## i64
  while i < selected_count
    distance = ffw_popcount(value ^ selected_values[i]) ## i64
    if distance < best
      best = distance
    i += 1
  best

# Selected factors, their pairwise XOR closure, and `nearby` globally closest
# factors.  At five selected terms and nearby <= 8, 32 slots are sufficient.
-> ffm_axis_pool(us, vs, ws, rank, selected, axis, nearby, values) (i64[] i64[] i64[] i64 i64[] i64 i64 i64[]) i64
  selected_values = i64[5]
  selected_count = 0 ## i64
  i = 0 ## i64
  while i < 5
    value = ffm_axis_value(us, vs, ws, selected[i], axis) ## i64
    selected_count = ffm_add_unique(selected_values, selected_count, 5, value)
    i += 1
  count = 0 ## i64
  i = 0
  while i < selected_count
    count = ffm_add_unique(values, count, 32, selected_values[i])
    i += 1
  left = 0 ## i64
  while left < selected_count
    right = left + 1 ## i64
    while right < selected_count
      count = ffm_add_unique(values, count, 32, selected_values[left] ^ selected_values[right])
      right += 1
    left += 1
  added = 0 ## i64
  while added < nearby
    best_value = 0 ## i64
    best_distance = 999999999 ## i64
    best_bits = 999999999 ## i64
    term = 0 ## i64
    while term < rank
      candidate = ffm_axis_value(us, vs, ws, term, axis) ## i64
      if candidate != 0 && ffm_contains(values, count, candidate) == 0
        distance = ffm_min_axis_distance(candidate, selected_values, selected_count) ## i64
        bits = ffw_popcount(candidate) ## i64
        better = 0 ## i64
        if distance < best_distance
          better = 1
        if distance == best_distance
          if bits < best_bits
            better = 1
          if bits == best_bits
            if best_value == 0 || candidate < best_value
              better = 1
        if better == 1
          best_value = candidate
          best_distance = distance
          best_bits = bits
      term += 1
    if best_value == 0
      added = nearby
    else
      count = ffm_add_unique(values, count, 32, best_value)
      added += 1
  count

-> ffm_pair_less(score, left, right, other_score, other_left, other_right) (i64 i64 i64 i64 i64 i64) i64
  less = 0 ## i64
  if score < other_score
    less = 1
  if score == other_score
    if left < other_left
      less = 1
    if left == other_left && right < other_right
      less = 1
  less

-> ffm_pair_score(us, vs, ws, left, right) (i64[] i64[] i64[] i64 i64) i64
  support = ffw_popcount(us[left] | us[right]) ## i64
  support += ffw_popcount(vs[left] | vs[right])
  support += ffw_popcount(ws[left] | ws[right])
  adjacency = ffw_popcount(us[left] ^ us[right]) ## i64
  adjacency += ffw_popcount(vs[left] ^ vs[right])
  adjacency += ffw_popcount(ws[left] ^ ws[right])
  support * 1000 + adjacency

# Keep the best bounded pair anchors in stable score/index order.
-> ffm_pair_beam(us, vs, ws, rank, want, scores, lefts, rights) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  pair_count = rank * (rank - 1) / 2 ## i64
  limit = want ## i64
  if limit > pair_count
    limit = pair_count
  count = 0 ## i64
  left = 0 ## i64
  while left < rank
    right = left + 1 ## i64
    while right < rank
      score = ffm_pair_score(us, vs, ws, left, right) ## i64
      insert = 0 ## i64
      while insert < count
        if ffm_pair_less(score, left, right, scores[insert], lefts[insert], rights[insert]) == 1
          break
        insert += 1
      if count < limit
        move = count ## i64
        while move > insert
          scores[move] = scores[move - 1]
          lefts[move] = lefts[move - 1]
          rights[move] = rights[move - 1]
          move -= 1
        scores[insert] = score
        lefts[insert] = left
        rights[insert] = right
        count += 1
      else
        if insert < limit
          move = limit - 1 ## i64
          while move > insert
            scores[move] = scores[move - 1]
            lefts[move] = lefts[move - 1]
            rights[move] = rights[move - 1]
            move -= 1
          scores[insert] = score
          lefts[insert] = left
          rights[insert] = right
      right += 1
    left += 1
  count

-> ffm_subset_score(us, vs, ws, selected, count, candidate) (i64[] i64[] i64[] i64[] i64 i64) i64
  uu = us[candidate] ## i64
  vv = vs[candidate] ## i64
  ww = ws[candidate] ## i64
  i = 0 ## i64
  while i < count
    uu = uu | us[selected[i]]
    vv = vv | vs[selected[i]]
    ww = ww | ws[selected[i]]
    i += 1
  support = ffw_popcount(uu) + ffw_popcount(vv) + ffw_popcount(ww) ## i64
  adjacency = 0 ## i64
  i = 0
  while i < count
    adjacency += ffw_popcount(us[selected[i]] ^ us[candidate])
    adjacency += ffw_popcount(vs[selected[i]] ^ vs[candidate])
    adjacency += ffw_popcount(ws[selected[i]] ^ ws[candidate])
    j = i + 1 ## i64
    while j < count
      adjacency += ffw_popcount(us[selected[i]] ^ us[selected[j]])
      adjacency += ffw_popcount(vs[selected[i]] ^ vs[selected[j]])
      adjacency += ffw_popcount(ws[selected[i]] ^ ws[selected[j]])
      j += 1
    i += 1
  support * 1000 + adjacency

-> ffm_sort_five(values) (i64[]) i64
  i = 1 ## i64
  while i < 5
    value = values[i] ## i64
    j = i ## i64
    while j > 0 && values[j - 1] > value
      values[j] = values[j - 1]
      j -= 1
    values[j] = value
    i += 1
  1

-> ffm_make_subset(us, vs, ws, rank, anchor_left, anchor_right, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  selected[0] = anchor_left
  selected[1] = anchor_right
  count = 2 ## i64
  while count < 5
    best = 0 - 1 ## i64
    best_score = 999999999 ## i64
    candidate = 0 ## i64
    while candidate < rank
      if ffm_selected_index(selected, count, candidate) == 0
        score = ffm_subset_score(us, vs, ws, selected, count, candidate) ## i64
        if score < best_score || (score == best_score && (best < 0 || candidate < best))
          best = candidate
          best_score = score
      candidate += 1
    if best < 0
      return 0
    selected[count] = best
    count += 1
  z = ffm_sort_five(selected) ## i64
  1

-> ffm_same_subset(flat, count, selected) (i64[] i64 i64[]) i64
  same = 0 ## i64
  row = 0 ## i64
  while row < count
    equal = 1 ## i64
    j = 0 ## i64
    while j < 5
      if flat[row * 5 + j] != selected[j]
        equal = 0
      j += 1
    if equal == 1
      same = 1
      row = count
    else
      row += 1
  same

-> ffm_candidate_better(score, bits, u, v, w, other_score, other_bits, other_u, other_v, other_w) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  better = 0 ## i64
  if score < other_score
    better = 1
  if score == other_score
    if bits < other_bits
      better = 1
    if bits == other_bits
      if u < other_u
        better = 1
      if u == other_u
        if v < other_v
          better = 1
        if v == other_v && w < other_w
          better = 1
  better

-> ffm_candidate_present(cu, cv, cw, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if cu[i] == u && cv[i] == v && cw[i] == w
      found = 1
      i = count
    else
      i += 1
  found

# Connectivity-biased bounded Cartesian product.  The five selected terms are
# protected at the head; remaining slots are ordered by selected-factor
# distance, density, and lexicographic factor tuple.
-> ffm_candidates(us, vs, ws, rank, selected, limit, nearby, cu, cv, cw) (i64[] i64[] i64[] i64 i64[] i64 i64 i64[] i64[] i64[]) i64
  pu = i64[32]
  pv = i64[32]
  pw = i64[32]
  nu = ffm_axis_pool(us, vs, ws, rank, selected, 0, nearby, pu) ## i64
  nv = ffm_axis_pool(us, vs, ws, rank, selected, 1, nearby, pv) ## i64
  nw = ffm_axis_pool(us, vs, ws, rank, selected, 2, nearby, pw) ## i64
  su = i64[5]
  sv = i64[5]
  sw = i64[5]
  i = 0 ## i64
  while i < 5
    su[i] = us[selected[i]]
    sv[i] = vs[selected[i]]
    sw[i] = ws[selected[i]]
    i += 1
  count = 0 ## i64
  i = 0
  while i < 5 && count < limit
    u = su[i] ## i64
    v = sv[i] ## i64
    w = sw[i] ## i64
    if ffm_candidate_present(cu, cv, cw, count, u, v, w) == 0
      cu[count] = u
      cv[count] = v
      cw[count] = w
      count += 1
    i += 1
  anchor_count = count ## i64
  scores = i64[limit]
  densities = i64[limit]
  a = 0 ## i64
  while a < nu
    b = 0 ## i64
    while b < nv
      c = 0 ## i64
      while c < nw
        u = pu[a] ## i64
        v = pv[b] ## i64
        w = pw[c] ## i64
        if ffm_candidate_present(cu, cv, cw, anchor_count, u, v, w) == 0
          score = ffm_min_axis_distance(u, su, 5) ## i64
          score += ffm_min_axis_distance(v, sv, 5)
          score += ffm_min_axis_distance(w, sw, 5)
          bits = ffw_popcount(u) + ffw_popcount(v) + ffw_popcount(w) ## i64
          insert = anchor_count ## i64
          while insert < count
            if ffm_candidate_better(score, bits, u, v, w, scores[insert], densities[insert], cu[insert], cv[insert], cw[insert]) == 1
              break
            insert += 1
          if count < limit
            move = count ## i64
            while move > insert
              scores[move] = scores[move - 1]
              densities[move] = densities[move - 1]
              cu[move] = cu[move - 1]
              cv[move] = cv[move - 1]
              cw[move] = cw[move - 1]
              move -= 1
            scores[insert] = score
            densities[insert] = bits
            cu[insert] = u
            cv[insert] = v
            cw[insert] = w
            count += 1
          else
            if insert < limit
              move = limit - 1 ## i64
              while move > insert
                scores[move] = scores[move - 1]
                densities[move] = densities[move - 1]
                cu[move] = cu[move - 1]
                cv[move] = cv[move - 1]
                cw[move] = cw[move - 1]
                move -= 1
              scores[insert] = score
              densities[insert] = bits
              cu[insert] = u
              cv[insert] = v
              cw[insert] = w
        c += 1
      b += 1
    a += 1
  count

# Python's reference fingerprint XOR-folds 128-bit chunks with a 29-bit
# rotation.  Compute the same linear projection directly from tensor support,
# avoiding a potentially large host integer. Four u32 words preserve all 128
# bits. The shape-aware entry point is shared by square and rectangular MITM
# lanes; the historical square wrapper remains source-compatible.
-> ffm_fingerprint_shape(u, v, w, udim, vdim, wdim, out) (i64 i64 i64 i64 i64 i64 i64[]) i64
  out[0] = 0
  out[1] = 0
  out[2] = 0
  out[3] = 0
  ai = 0 ## i64
  while ai < udim
    if ((u >> ai) & 1) == 1
      bi = 0 ## i64
      while bi < vdim
        if ((v >> bi) & 1) == 1
          ci = 0 ## i64
          while ci < wdim
            if ((w >> ci) & 1) == 1
              position = (ai * vdim + bi) * wdim + ci ## i64
              chunk = position / 128 ## i64
              bit = position % 128 ## i64
              projected = (bit + ((chunk * 29) % 128)) % 128 ## i64
              word = projected / 32 ## i64
              shift = projected % 32 ## i64
              out[word] = out[word] ^ (1 << shift)
            ci += 1
        bi += 1
    ai += 1
  1

-> ffm_fingerprint(u, v, w, dim, out) (i64 i64 i64 i64 i64[]) i64
  ffm_fingerprint_shape(u, v, w, dim, dim, dim, out)

-> ffm_target_fingerprint_shape(us, vs, ws, selected, udim, vdim, wdim, out) (i64[] i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  out[0] = 0
  out[1] = 0
  out[2] = 0
  out[3] = 0
  words = i64[4]
  i = 0 ## i64
  while i < 5
    z = ffm_fingerprint_shape(us[selected[i]], vs[selected[i]], ws[selected[i]], udim, vdim, wdim, words) ## i64
    j = 0 ## i64
    while j < 4
      out[j] = out[j] ^ words[j]
      j += 1
    i += 1
  1

-> ffm_target_fingerprint(us, vs, ws, selected, dim, out) (i64[] i64[] i64[] i64[] i64 i64[]) i64
  ffm_target_fingerprint_shape(us, vs, ws, selected, dim, dim, dim, out)

-> ffm_local_exact_shape(us, vs, ws, selected, cu, cv, cw, indices, udim, vdim, wdim) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  ok = 1 ## i64
  ai = 0 ## i64
  while ai < udim && ok == 1
    bi = 0 ## i64
    while bi < vdim && ok == 1
      ci = 0 ## i64
      while ci < wdim && ok == 1
        parity = 0 ## i64
        t = 0 ## i64
        while t < 5
          source = selected[t] ## i64
          if ((us[source] >> ai) & 1) == 1
            if ((vs[source] >> bi) & 1) == 1
              if ((ws[source] >> ci) & 1) == 1
                parity = parity ^ 1
          t += 1
        t = 0
        while t < 4
          source = indices[t] ## i64
          if ((cu[source] >> ai) & 1) == 1
            if ((cv[source] >> bi) & 1) == 1
              if ((cw[source] >> ci) & 1) == 1
                parity = parity ^ 1
          t += 1
        if parity != 0
          ok = 0
        ci += 1
      bi += 1
    ai += 1
  ok

-> ffm_local_exact(us, vs, ws, selected, cu, cv, cw, indices, n) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  dim = n * n ## i64
  ffm_local_exact_shape(us, vs, ws, selected, cu, cv, cw, indices, dim, dim, dim)

-> ffm_toggle_plain(us, vs, ws, rank, cap, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return rank
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      found = i
      i = rank
    else
      i += 1
  if found >= 0
    last = rank - 1 ## i64
    us[found] = us[last]
    vs[found] = vs[last]
    ws[found] = ws[last]
    return last
  if rank >= cap
    return 0 - 1
  us[rank] = u
  vs[rank] = v
  ws[rank] = w
  rank + 1

-> ffm_accept_and_dump(us, vs, ws, rank, selected, cu, cv, cw, indices, n, output_path) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64 String) i64
  cap = ffw_default_capacity(n) ## i64
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffm_selected_index(selected, 5, i) == 0
      outu[out_rank] = us[i]
      outv[out_rank] = vs[i]
      outw[out_rank] = ws[i]
      out_rank += 1
    i += 1
  i = 0
  while i < 4 && out_rank >= 0
    source = indices[i] ## i64
    out_rank = ffm_toggle_plain(outu, outv, outw, out_rank, cap, cu[source], cv[source], cw[source])
    i += 1
  if out_rank < 1 || out_rank >= rank
    return 0
  state_size = ffw_state_size(cap) ## i64
  candidate = i64[state_size]
  loaded = ffw_init_terms_cap(candidate, outu, outv, outw, out_rank, n, cap, 7777, 0, 1, 1, 1) ## i64
  if loaded != out_rank
    return 0
  # ffw_init_terms_cap performs one exhaustive gate.  ffw_dump_best performs
  # an independent second exhaustive gate immediately before the write.
  dumped = ffw_dump_best(candidate, output_path) ## i64
  if dumped != out_rank
    return 0
  out_rank

## u32[]: hp0, hp1, hp2, hp3, used, ht0, ht1, ht2, ht3, hpair
## i64: hcount, hcap, left, right, pair_index, p0, p1, p2, p3, mixed, slot
fn ffm_build_table(hp0, hp1, hp2, hp3, used, ht0, ht1, ht2, ht3, hpair, hcount, hcap)
  left = 0
  while left < hcount
    right = left + 1
    while right < hcount
      pair_index = left * hcount + right
      p0 = hp0[pair_index]
      p1 = hp1[pair_index]
      p2 = hp2[pair_index]
      p3 = hp3[pair_index]
      mixed = ffm_hash4(p0, p1, p2, p3)
      slot = mixed & (hcap - 1)
      while used[slot] != 0
        slot = (slot + 1) & (hcap - 1)
      used[slot] = 1
      ht0[slot] = p0
      ht1[slot] = p1
      ht2[slot] = p2
      ht3[slot] = p3
      hpair[slot] = pair_index
      right += 1
    left += 1
  1

# Match ffm_probe_pairs' u32 hash using nonnegative masked i64 arithmetic.
# 4,294,967,295 * 73,244,475 stays comfortably within signed i64.
fn ffm_hash4(p0, p1, p2, p3)
  mask = 4294967295
  x0 = p0 & mask
  x1 = p1 & mask
  x2 = p2 & mask
  x3 = p3 & mask
  r1 = ((x1 << 7) & mask) | (x1 >> 25)
  r2 = ((x2 << 13) & mask) | (x2 >> 19)
  r3 = ((x3 << 19) & mask) | (x3 >> 13)
  mixed = (x0 ^ r1 ^ r2 ^ r3) & mask
  mixed = ((mixed ^ (mixed >> 16)) * 73244475) & mask
  mixed = ((mixed ^ (mixed >> 16)) * 73244475) & mask
  (mixed ^ (mixed >> 16)) & mask

# One exact subset dispatch.  metrics:
# [candidates,pairs,table,enum_ms,table_ms,probe_ms,fingerprint_hits,exact_checks]
-> ffm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, output_path, metrics)
  square = count * count ## i64
  host_fps0 = metal_array(32, count)
  host_fps1 = metal_array(32, count)
  host_fps2 = metal_array(32, count)
  host_fps3 = metal_array(32, count)
  words = i64[4]
  dim = n * n ## i64
  i = 0 ## i64
  while i < count
    z = ffm_fingerprint(cu[i], cv[i], cw[i], dim, words) ## i64
    host_fps0[i] = words[0]
    host_fps1[i] = words[1]
    host_fps2[i] = words[2]
    host_fps3[i] = words[3]
    i += 1
  target_words = i64[4]
  z = ffm_target_fingerprint(us, vs, ws, selected, dim, target_words) ## i64

  host_pair0 = metal_array(32, square)
  host_pair1 = metal_array(32, square)
  host_pair2 = metal_array(32, square)
  host_pair3 = metal_array(32, square)
  host_enum_params = metal_array(32, 1)
  host_enum_params[0] = count
  fps0_buf = metal_buffer_for(device, host_fps0)
  fps1_buf = metal_buffer_for(device, host_fps1)
  fps2_buf = metal_buffer_for(device, host_fps2)
  fps3_buf = metal_buffer_for(device, host_fps3)
  pair0_buf = metal_buffer_for(device, host_pair0)
  pair1_buf = metal_buffer_for(device, host_pair1)
  pair2_buf = metal_buffer_for(device, host_pair2)
  pair3_buf = metal_buffer_for(device, host_pair3)
  enum_params_buf = metal_buffer_for(device, host_enum_params)
  t0 = ccall("__w_clock_ms") ## i64
  metal_dispatch_n(queue, enum_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, pair0_buf, pair1_buf, pair2_buf, pair3_buf, enum_params_buf], square)
  t1 = ccall("__w_clock_ms") ## i64

  pairs = count * (count - 1) / 2 ## i64
  active_cap = 1 ## i64
  while active_cap < pairs * 2
    active_cap *= 2
  host_used = metal_array(32, active_cap)
  host_table0 = metal_array(32, active_cap)
  host_table1 = metal_array(32, active_cap)
  host_table2 = metal_array(32, active_cap)
  host_table3 = metal_array(32, active_cap)
  host_table_pair = metal_array(32, active_cap)
  z = ffm_build_table(host_pair0, host_pair1, host_pair2, host_pair3, host_used, host_table0, host_table1, host_table2, host_table3, host_table_pair, count, active_cap) ## i64
  t2 = ccall("__w_clock_ms") ## i64

  host_target = metal_array(32, 4)
  i = 0
  while i < 4
    host_target[i] = target_words[i]
    i += 1
  host_matches = metal_array(32, square * 16)
  host_probe_params = metal_array(32, 3)
  host_probe_params[0] = count
  host_probe_params[1] = active_cap - 1
  host_probe_params[2] = active_cap
  table0_buf = metal_buffer_for(device, host_table0)
  table1_buf = metal_buffer_for(device, host_table1)
  table2_buf = metal_buffer_for(device, host_table2)
  table3_buf = metal_buffer_for(device, host_table3)
  table_used_buf = metal_buffer_for(device, host_used)
  table_pair_buf = metal_buffer_for(device, host_table_pair)
  target_buf = metal_buffer_for(device, host_target)
  matches_buf = metal_buffer_for(device, host_matches)
  probe_params_buf = metal_buffer_for(device, host_probe_params)
  metal_dispatch_n(queue, probe_pipeline, [fps0_buf, fps1_buf, fps2_buf, fps3_buf, table0_buf, table1_buf, table2_buf, table3_buf, table_used_buf, table_pair_buf, target_buf, matches_buf, probe_params_buf], square)
  t3 = ccall("__w_clock_ms") ## i64

  hit_rank = 0 ## i64
  fingerprint_hits = 0 ## i64
  exact_checks = 0 ## i64
  indices = i64[4]
  left = 0 ## i64
  while left < count && hit_rank == 0
    right = left + 1 ## i64
    while right < count && hit_rank == 0
      query_index = left * count + right ## i64
      h = 0 ## i64
      while h < 16 && hit_rank == 0
        packed = host_matches[query_index * 16 + h] ## i64
        if packed > 0
          fingerprint_hits += 1
          other_left = packed / count ## i64
          other_right = packed - other_left * count ## i64
          indices[0] = left
          indices[1] = right
          indices[2] = other_left
          indices[3] = other_right
          exact_checks += 1
          if ffm_local_exact(us, vs, ws, selected, cu, cv, cw, indices, n) == 1
            hit_rank = ffm_accept_and_dump(us, vs, ws, rank, selected, cu, cv, cw, indices, n, output_path)
        h += 1
      right += 1
    left += 1
  metrics[0] = count
  metrics[1] = pairs
  metrics[2] = active_cap
  metrics[3] = t1 - t0
  metrics[4] = t2 - t1
  metrics[5] = t3 - t2
  metrics[6] = fingerprint_hits
  metrics[7] = exact_checks
  hit_rank

-> ffm_load_exact(seed_path, n)
  cap = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(cap) ## i64
  state = i64[state_size]
  rank = ffw_load_scheme_cap(state, seed_path, n, cap, 9191, 0, 1, 1, 1) ## i64
  if rank < 5
    return nil
  if ffw_verify_best_exact(state, n) != 1
    return nil
  state

-> ffm_search_loaded(state, output_path, n, subsets, pool, nearby, offset, explicit_subset, metal_path, metallib_path = "")
  rank = ffw_best_rank(state) ## i64
  cap = ffw_default_capacity(n) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  exported = ffw_export_best(state, us, vs, ws) ## i64
  if exported != rank
    return 0 - 10
  device = metal_device()
  library = nil
  if metallib_path != ""
    library = metal_load_library(device, metallib_path)
  if library == nil
    msl = read_file(metal_path)
    if msl == nil || msl.size() == 0
      return 0 - 11
    library = metal_compile_source(device, msl)
  enum_pipeline = metal_pipeline(library, "ffm_enumerate_pairs")
  probe_pipeline = metal_pipeline(library, "ffm_probe_pairs")
  queue = metal_queue(device)

  tested = 0 ## i64
  hit_rank = 0 ## i64
  total_candidates = 0 ## i64
  total_pairs = 0 ## i64
  total_fp_hits = 0 ## i64
  total_exact_checks = 0 ## i64
  total_enum_ms = 0 ## i64
  total_table_ms = 0 ## i64
  total_probe_ms = 0 ## i64
  processed = i64[subsets * 5]

  if explicit_subset != nil
    selected = explicit_subset
    valid = 1 ## i64
    i = 0 ## i64
    while i < 5
      if selected[i] < 0 || selected[i] >= rank
        valid = 0
      j = 0 ## i64
      while j < i
        if selected[j] == selected[i]
          valid = 0
        j += 1
      i += 1
    if valid == 0
      return 0 - 12
    z = ffm_sort_five(selected) ## i64
    cu = i64[pool]
    cv = i64[pool]
    cw = i64[pool]
    count = ffm_candidates(us, vs, ws, rank, selected, pool, nearby, cu, cv, cw) ## i64
    metrics = i64[8]
    hit_rank = ffm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, output_path, metrics) ## i64
    tested = 1
    total_candidates = metrics[0]
    total_pairs = metrics[1]
    total_enum_ms = metrics[3]
    total_table_ms = metrics[4]
    total_probe_ms = metrics[5]
    total_fp_hits = metrics[6]
    total_exact_checks = metrics[7]
    << "GPU_MITM_NATIVE_SUBSET ordinal=1 indices=" + selected[0].to_s() + "," + selected[1].to_s() + "," + selected[2].to_s() + "," + selected[3].to_s() + "," + selected[4].to_s() + " candidates=" + count.to_s() + " fingerprint_hits=" + metrics[6].to_s() + " exact_checks=" + metrics[7].to_s() + " hit_rank=" + hit_rank.to_s()
  else
    pair_count = rank * (rank - 1) / 2 ## i64
    window = pair_count ## i64
    if window > 256
      window = 256
    effective_offset = offset % window ## i64
    want = effective_offset + subsets * 8 ## i64
    if want > pair_count
      want = pair_count
    scores = i64[want]
    lefts = i64[want]
    rights = i64[want]
    beam_count = ffm_pair_beam(us, vs, ws, rank, want, scores, lefts, rights) ## i64
    cursor = effective_offset ## i64
    while cursor < beam_count && tested < subsets && hit_rank == 0
      selected = i64[5]
      made = ffm_make_subset(us, vs, ws, rank, lefts[cursor], rights[cursor], selected) ## i64
      if made == 1
        if ffm_same_subset(processed, tested, selected) == 0
          j = 0 ## i64
          while j < 5
            processed[tested * 5 + j] = selected[j]
            j += 1
          cu = i64[pool]
          cv = i64[pool]
          cw = i64[pool]
          count = ffm_candidates(us, vs, ws, rank, selected, pool, nearby, cu, cv, cw) ## i64
          metrics = i64[8]
          hit_rank = ffm_gpu_subset(device, enum_pipeline, probe_pipeline, queue, us, vs, ws, rank, selected, cu, cv, cw, count, n, output_path, metrics) ## i64
          tested += 1
          total_candidates += metrics[0]
          total_pairs += metrics[1]
          total_enum_ms += metrics[3]
          total_table_ms += metrics[4]
          total_probe_ms += metrics[5]
          total_fp_hits += metrics[6]
          total_exact_checks += metrics[7]
          << "GPU_MITM_NATIVE_SUBSET ordinal=" + tested.to_s() + " indices=" + selected[0].to_s() + "," + selected[1].to_s() + "," + selected[2].to_s() + "," + selected[3].to_s() + "," + selected[4].to_s() + " candidates=" + count.to_s() + " fingerprint_hits=" + metrics[6].to_s() + " exact_checks=" + metrics[7].to_s() + " hit_rank=" + hit_rank.to_s()
      cursor += 1
  hit = 0 ## i64
  if hit_rank > 0
    hit = 1
  << "GPU_MITM_NATIVE_RESULT dimension=" + n.to_s() + " rank=" + rank.to_s() + " tested=" + tested.to_s() + " candidates=" + total_candidates.to_s() + " pairs=" + total_pairs.to_s() + " enum_ms=" + total_enum_ms.to_s() + " table_ms=" + total_table_ms.to_s() + " probe_ms=" + total_probe_ms.to_s() + " fingerprint_hits=" + total_fp_hits.to_s() + " exact_checks=" + total_exact_checks.to_s() + " hit=" + hit.to_s() + " output_rank=" + hit_rank.to_s()
  hit

-> ffm_search(seed_path, output_path, n, subsets, pool, nearby, offset, metal_path, metallib_path = "")
  if ffm_plan_valid(n, subsets, pool, nearby, offset) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  z = write_file(output_path, "")
  state = ffm_load_exact(seed_path, n)
  if state == nil
    return 0 - 2
  << "GPU_MITM_NATIVE_START dimension=" + n.to_s() + " rank=" + ffw_best_rank(state).to_s() + " subsets=" + subsets.to_s() + " pool=" + pool.to_s() + " nearby=" + nearby.to_s() + " offset=" + offset.to_s()
  ffm_search_loaded(state, output_path, n, subsets, pool, nearby, offset, nil, metal_path, metallib_path)

-> ffm_search_exact_subset(seed_path, output_path, n, pool, nearby, selected, metal_path, metallib_path = "")
  if ffm_plan_valid(n, 1, pool, nearby, 0) == 0
    return 0 - 1
  if seed_path == output_path
    return 0 - 3
  z = write_file(output_path, "")
  state = ffm_load_exact(seed_path, n)
  if state == nil
    return 0 - 2
  << "GPU_MITM_NATIVE_START dimension=" + n.to_s() + " rank=" + ffw_best_rank(state).to_s() + " subsets=1 pool=" + pool.to_s() + " nearby=" + nearby.to_s() + " offset=explicit"
  ffm_search_loaded(state, output_path, n, 1, pool, nearby, 0, selected, metal_path, metallib_path)
