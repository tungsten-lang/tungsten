# GPU-backed complete local factor-span refactoring for FlipFleet.
#
# The host uses flipfleet_span_refactor to build every rank-one tensor in the
# three selected factor spans.  Candidate signatures are exact local tensors:
# at most 27 bits for k=3 and exactly one signed i64 (including bit 63) for
# k=4.  Metal therefore performs an exact join, not a fingerprint filter.
#
# Four-term joins use a duplicate-preserving open-addressed pair table.  Every
# candidate pair gets its own slot even when many pairs have the same tensor
# signature.  At the worst supported neighborhood (3375 candidates) the table
# has 8,388,608 slots: about 101 MB for i64 signatures plus packed u32 pairs.
# Only one k=4 subset is admitted per child process.

## i64[]: signatures, target
## i32[]: control, params
@gpu fn ffsrp_probe_two(signatures, target, control, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  a = tid / count ## i32
  b = tid - a * count ## i32
  if a < b
    if (signatures[a] ^ signatures[b]) == target[0]
      old = gpu.atomic_min_i32(control, 0, tid) ## i32

## i64[]: signatures, table_signatures, target
## u32[]: table_codes
## i32[]: original_ids, control, params
@gpu fn ffsrp_probe_three(signatures, table_signatures, table_codes, target, original_ids, control, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## i32
  table_capacity = params[2] ## i32
  k = params[3] ## i32
  a = tid / count ## i32
  b = tid - a * count ## i32
  if a < b
    wanted = target[0] ^ signatures[a] ^ signatures[b] ## i64
    lo = wanted & 4294967295 ## i64
    hi = (wanted >> 32) & 4294967295 ## i64
    rotated = ((hi << 13) & 4294967295) | (hi >> 19) ## i64
    mixed = (lo ^ rotated ^ (lo >> 16) ^ (hi >> 11)) & 4294967295 ## i64
    mixed = (mixed * 1103515245 + 12345) & 4294967295
    mixed = mixed ^ (mixed >> 16)
    slot = mixed & table_mask ## i32
    scanned = 0 ## i32
    done = 0 ## i32
    while scanned < table_capacity
      if done == 0
        packed = table_codes[slot] ## u32
        if packed == 0
          done = 1
        else
          if table_signatures[slot] == wanted
            third = packed - 1 ## i32
            distinct = 1 ## i32
            if third == a
              distinct = 0
            if third == b
              distinct = 0
            if distinct != 0
              unchanged = 0 ## i32
              if k == 3
                in_a = 0 ## i32
                in_b = 0 ## i32
                in_third = 0 ## i32
                oi = 0 ## i32
                while oi < 3
                  if original_ids[oi] == a
                    in_a = 1
                  if original_ids[oi] == b
                    in_b = 1
                  if original_ids[oi] == third
                    in_third = 1
                  oi = oi + 1
                if in_a != 0
                  if in_b != 0
                    if in_third != 0
                      unchanged = 1
              if unchanged == 0
                old = gpu.atomic_min_i32(control, 0, tid) ## i32
                done = 1
          if done == 0
            slot = (slot + 1) & table_mask
            scanned = scanned + 1
      else
        scanned = table_capacity

## i64[]: signatures, table_signatures, target
## u32[]: table_codes
## i32[]: original_ids, control, params
@gpu fn ffsrp_probe_four(signatures, table_signatures, table_codes, target, original_ids, control, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## i32
  table_capacity = params[2] ## i32
  k = params[3] ## i32
  a = tid / count ## i32
  b = tid - a * count ## i32
  if a < b
    wanted = target[0] ^ signatures[a] ^ signatures[b] ## i64
    lo = wanted & 4294967295 ## i64
    hi = (wanted >> 32) & 4294967295 ## i64
    rotated = ((hi << 13) & 4294967295) | (hi >> 19) ## i64
    mixed = (lo ^ rotated ^ (lo >> 16) ^ (hi >> 11)) & 4294967295 ## i64
    mixed = (mixed * 1103515245 + 12345) & 4294967295
    mixed = mixed ^ (mixed >> 16)
    slot = mixed & table_mask ## i32
    scanned = 0 ## i32
    done = 0 ## i32
    while scanned < table_capacity
      if done == 0
        packed = table_codes[slot] ## u32
        if packed == 0
          done = 1
        else
          if table_signatures[slot] == wanted
            code = packed - 1 ## i32
            c = code / count ## i32
            d = code - c * count ## i32
            distinct = 1 ## i32
            if c == a
              distinct = 0
            if c == b
              distinct = 0
            if d == a
              distinct = 0
            if d == b
              distinct = 0
            if distinct != 0
              unchanged = 0 ## i32
              if k == 4
                in_a = 0 ## i32
                in_b = 0 ## i32
                in_c = 0 ## i32
                in_d = 0 ## i32
                oi = 0 ## i32
                while oi < 4
                  if original_ids[oi] == a
                    in_a = 1
                  if original_ids[oi] == b
                    in_b = 1
                  if original_ids[oi] == c
                    in_c = 1
                  if original_ids[oi] == d
                    in_d = 1
                  oi = oi + 1
                if in_a != 0
                  if in_b != 0
                    if in_c != 0
                      if in_d != 0
                        unchanged = 1
              if unchanged == 0
                old = gpu.atomic_min_i32(control, 0, tid) ## i32
                done = 1
          if done == 0
            slot = (slot + 1) & table_mask
            scanned = scanned + 1
      else
        scanned = table_capacity

use core/metal
use flipfleet_span_refactor

# This hash is intentionally expressed with signed-i64 operations on both the
# host and Metal.  The final mask uses at most 23 bits, so arithmetic right
# shift and two's-complement representation agree exactly even for bit 63.
-> ffsrp_hash(signature, mask) (i64 i64) i64
  lo = signature & 4294967295 ## i64
  hi = (signature >> 32) & 4294967295 ## i64
  rotated = ((hi << 13) & 4294967295) | (hi >> 19) ## i64
  mixed = (lo ^ rotated ^ (lo >> 16) ^ (hi >> 11)) & 4294967295 ## i64
  mixed = (mixed * 1103515245 + 12345) & 4294967295
  mixed = mixed ^ (mixed >> 16)
  mixed & mask

-> ffsrp_open_capacity(entries) (i64) i64
  # Keep at least 20% slack.  The worst table lands at 67.9% occupancy.
  wanted = entries + (entries + 3) / 4 ## i64
  capacity = 16 ## i64
  while capacity < wanted
    capacity *= 2
  capacity

# Insert one entry without coalescing equal signatures.  `packed_code` is
# stored plus one, reserving zero as the empty-slot marker.
-> ffsrp_insert(table_signatures, table_codes, capacity, signature, packed_code) (i64[] u32[] i64 i64 i64) i64
  slot = ffsrp_hash(signature, capacity - 1) ## i64
  scanned = 0 ## i64
  while table_codes[slot] != 0 && scanned < capacity
    slot = (slot + 1) & (capacity - 1)
    scanned += 1
  if scanned >= capacity
    return 0
  table_signatures[slot] = signature
  table_codes[slot] = packed_code + 1
  1

-> ffsrp_same_original(ids, count, original_ids, k) (i64[] i64 i64[] i64) i64
  same = 0 ## i64
  if count == k
    same = ffsr_ids_same_set(ids, count, original_ids, k)
  same

-> ffsrp_resolve_three(signatures, table_signatures, table_codes, capacity, count, target, original_ids, k, a, b, out_ids) (i64[] i64[] u32[] i64 i64 i64 i64[] i64 i64 i64 i64[]) i64
  result = 0 ## i64
  wanted = target ^ signatures[a] ^ signatures[b] ## i64
  slot = ffsrp_hash(wanted, capacity - 1) ## i64
  scanned = 0 ## i64
  while scanned < capacity && table_codes[slot] != 0 && result == 0
    if table_signatures[slot] == wanted
      third = table_codes[slot] - 1 ## i64
      if third != a && third != b
        out_ids[0] = a
        out_ids[1] = b
        out_ids[2] = third
        if ffsr_accept_ids(out_ids, 3, original_ids, k) == 1
          result = 3
    slot = (slot + 1) & (capacity - 1)
    scanned += 1
  result

-> ffsrp_resolve_four(signatures, table_signatures, table_codes, capacity, count, target, original_ids, k, a, b, out_ids) (i64[] i64[] u32[] i64 i64 i64 i64[] i64 i64 i64 i64[]) i64
  result = 0 ## i64
  wanted = target ^ signatures[a] ^ signatures[b] ## i64
  slot = ffsrp_hash(wanted, capacity - 1) ## i64
  scanned = 0 ## i64
  while scanned < capacity && table_codes[slot] != 0 && result == 0
    if table_signatures[slot] == wanted
      code = table_codes[slot] - 1 ## i64
      c = code / count ## i64
      d = code - c * count ## i64
      if c != a && c != b && d != a && d != b
        out_ids[0] = a
        out_ids[1] = b
        out_ids[2] = c
        out_ids[3] = d
        if ffsr_accept_ids(out_ids, 4, original_ids, k) == 1
          result = 4
    slot = (slot + 1) & (capacity - 1)
    scanned += 1
  result

# Prefer exact local replacements that contain one or more terms already live
# outside the selected window.  Such terms cancel under GF(2) parity, so a
# nominal 3->4 hit with one collision is an actual global 3->2 rank drop.
# `stats` records external candidate ids, exact tuples examined, winning
# collision count, and result cardinality.
-> ffsrp_find_collision_ids_scratch(cu, cv, cw, signatures, count, target, original_ids, k, want, external_u, external_v, external_w, external_count, out_ids, stats, is_external, table) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i32[]) i64
  i = 0 ## i64
  while i < 4
    stats[i] = 0
    i += 1
  result = 0 ## i64
  if ffsr_move_supported(k,want) == 0 || count < want || external_count < 1
    return 0
  capacity = ffsr_single_table_capacity(count) ## i64
  if is_external.size() < count || table.size() < capacity
    return 0
  i = 0
  while i < count
    is_external[i] = 0
    i += 1
  i = 0
  while i < capacity
    table[i] = 0
    i += 1
  i = 0
  while i < external_count
    candidate = ffsr_find_candidate_term(cu,cv,cw,count,external_u[i],external_v[i],external_w[i]) ## i64
    if candidate >= 0 && is_external[candidate] == 0
      is_external[candidate] = 1
      stats[0] += 1
    i += 1
  if stats[0] == 0
    return 0

  z = ffsr_build_single_table(signatures,count,table,capacity-1) ## i64
  best_collisions = 0 ## i64
  best_density = 9223372036854775807 ## i64
  candidate_ids = i64[4]

  if want == 2
    a = 0 ## i64
    while a < count
      b = a + 1 ## i64
      while b < count
        if is_external[a] != 0 || is_external[b] != 0
          stats[1] += 1
          if (signatures[a] ^ signatures[b]) == target
            candidate_ids[0] = a
            candidate_ids[1] = b
            if ffsr_accept_ids(candidate_ids,2,original_ids,k) == 1
              collisions = is_external[a] + is_external[b] ## i64
              density = ffw_popcount(cu[a]) + ffw_popcount(cv[a]) + ffw_popcount(cw[a]) + ffw_popcount(cu[b]) + ffw_popcount(cv[b]) + ffw_popcount(cw[b]) ## i64
              if collisions > best_collisions || (collisions == best_collisions && density < best_density)
                best_collisions = collisions
                best_density = density
                out_ids[0] = a
                out_ids[1] = b
                result = 2
        b += 1
      a += 1

  if want == 3
    a = 0
    while a < count
      b = a + 1
      while b < count
        third = ffsr_lookup_signature(signatures,table,capacity-1,target ^ signatures[a] ^ signatures[b]) ## i64
        stats[1] += 1
        if third > b
          candidate_ids[0] = a
          candidate_ids[1] = b
          candidate_ids[2] = third
          collisions = is_external[a] + is_external[b] + is_external[third] ## i64
          if collisions > 0 && ffsr_accept_ids(candidate_ids,3,original_ids,k) == 1
            density = ffw_popcount(cu[a]) + ffw_popcount(cv[a]) + ffw_popcount(cw[a]) + ffw_popcount(cu[b]) + ffw_popcount(cv[b]) + ffw_popcount(cw[b]) + ffw_popcount(cu[third]) + ffw_popcount(cv[third]) + ffw_popcount(cw[third]) ## i64
            if collisions > best_collisions || (collisions == best_collisions && density < best_density)
              best_collisions = collisions
              best_density = density
              out_ids[0] = a
              out_ids[1] = b
              out_ids[2] = third
              result = 3
        b += 1
      a += 1

  if want == 4
    fixed = 0 ## i64
    fixed_used = 0 ## i64
    fixed_limit = 8 ## i64
    if k == 3
      fixed_limit = 32
    while fixed < count && fixed_used < fixed_limit
      if is_external[fixed] != 0
        fixed_used += 1
        a = 0
        while a < count
          b = a + 1
          while b < count
            if a != fixed && b != fixed
              third = ffsr_lookup_signature(signatures,table,capacity-1,target ^ signatures[fixed] ^ signatures[a] ^ signatures[b]) ## i64
              stats[1] += 1
              if third >= 0 && third != fixed && third != a && third != b
                candidate_ids[0] = fixed
                candidate_ids[1] = a
                candidate_ids[2] = b
                candidate_ids[3] = third
                collisions = is_external[fixed] + is_external[a] + is_external[b] + is_external[third] ## i64
                if ffsr_accept_ids(candidate_ids,4,original_ids,k) == 1
                  density = ffw_popcount(cu[fixed]) + ffw_popcount(cv[fixed]) + ffw_popcount(cw[fixed]) + ffw_popcount(cu[a]) + ffw_popcount(cv[a]) + ffw_popcount(cw[a]) + ffw_popcount(cu[b]) + ffw_popcount(cv[b]) + ffw_popcount(cw[b]) + ffw_popcount(cu[third]) + ffw_popcount(cv[third]) + ffw_popcount(cw[third]) ## i64
                  if collisions > best_collisions || (collisions == best_collisions && density < best_density)
                    best_collisions = collisions
                    best_density = density
                    out_ids[0] = fixed
                    out_ids[1] = a
                    out_ids[2] = b
                    out_ids[3] = third
                    result = 4
            b += 1
          a += 1
      fixed += 1

  stats[2] = best_collisions
  stats[3] = result
  result

-> ffsrp_find_collision_ids(cu, cv, cw, signatures, count, target, original_ids, k, want, external_u, external_v, external_w, external_count, out_ids, stats) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64[] i64[] i64[] i64 i64[] i64[]) i64
  scratch_flags = i64[count]
  scratch_table = i32[ffsr_single_table_capacity(count)]
  ffsrp_find_collision_ids_scratch(cu,cv,cw,signatures,count,target,original_ids,k,want,external_u,external_v,external_w,external_count,out_ids,stats,scratch_flags,scratch_table)

# Exact GPU join over one already-built complete span.  `stats` has capacity
# six and records candidate count, query work, table entries/capacity, winning
# query id, and result count.
-> ffsrp_find_ids_gpu(device, library, queue, signatures, count, target_value, original_ids, k, want, out_ids, stats) i64
  i = 0 ## i64
  while i < 6
    stats[i] = 0
    i += 1
  stats[0] = count
  result = 0 ## i64
  if ffsr_move_supported(k, want) == 0 || count < want || count > ffsr_max_candidates(k)
    return 0
  gpu_signatures = metal_array(64, count)
  i = 0
  while i < count
    gpu_signatures[i] = signatures[i]
    i += 1
  gpu_target = metal_array(64, 1)
  gpu_target[0] = target_value
  gpu_originals = metal_array(32, 4)
  i = 0
  while i < 4
    gpu_originals[i] = original_ids[i]
    i += 1
  work = count * count ## i64
  control = metal_array(32, 1)
  control[0] = work
  params = metal_array(32, 4)
  params[0] = count
  params[1] = 0
  params[2] = 0
  params[3] = k
  stats[1] = work
  if want == 2
    pipeline2 = metal_pipeline(library, "ffsrp_probe_two")
    metal_dispatch_n(queue, pipeline2, [metal_buffer_for(device, gpu_signatures), metal_buffer_for(device, gpu_target), metal_buffer_for(device, control), metal_buffer_for(device, params)], work)
    winner = control[0] ## i64
    if winner < work
      a = winner / count ## i64
      b = winner - a * count ## i64
      out_ids[0] = a
      out_ids[1] = b
      if ffsr_accept_ids(out_ids, 2, original_ids, k) == 1
        result = 2
  if want == 3
    entries = count ## i64
    capacity = ffsrp_open_capacity(entries) ## i64
    table_signatures = metal_array(64, capacity)
    table_codes = metal_array(32, capacity) ## u32[]
    i = 0
    while i < count
      inserted = ffsrp_insert(table_signatures, table_codes, capacity, signatures[i], i) ## i64
      if inserted == 0
        return 0
      i += 1
    params[1] = capacity - 1
    params[2] = capacity
    pipeline3 = metal_pipeline(library, "ffsrp_probe_three")
    metal_dispatch_n(queue, pipeline3, [metal_buffer_for(device, gpu_signatures), metal_buffer_for(device, table_signatures), metal_buffer_for(device, table_codes), metal_buffer_for(device, gpu_target), metal_buffer_for(device, gpu_originals), metal_buffer_for(device, control), metal_buffer_for(device, params)], work)
    winner = control[0] ## i64
    if winner < work
      a = winner / count ## i64
      b = winner - a * count ## i64
      result = ffsrp_resolve_three(signatures, table_signatures, table_codes, capacity, count, target_value, original_ids, k, a, b, out_ids)
    stats[2] = entries
    stats[3] = capacity
  if want == 4
    entries = count * (count - 1) / 2 ## i64
    capacity = ffsrp_open_capacity(entries) ## i64
    table_signatures = metal_array(64, capacity)
    table_codes = metal_array(32, capacity) ## u32[]
    a = 0 ## i64
    while a < count
      b = a + 1 ## i64
      while b < count
        inserted = ffsrp_insert(table_signatures, table_codes, capacity, signatures[a] ^ signatures[b], a * count + b) ## i64
        if inserted == 0
          return 0
        b += 1
      a += 1
    params[1] = capacity - 1
    params[2] = capacity
    pipeline4 = metal_pipeline(library, "ffsrp_probe_four")
    metal_dispatch_n(queue, pipeline4, [metal_buffer_for(device, gpu_signatures), metal_buffer_for(device, table_signatures), metal_buffer_for(device, table_codes), metal_buffer_for(device, gpu_target), metal_buffer_for(device, gpu_originals), metal_buffer_for(device, control), metal_buffer_for(device, params)], work)
    winner = control[0] ## i64
    if winner < work
      a = winner / count ## i64
      b = winner - a * count ## i64
      result = ffsrp_resolve_four(signatures, table_signatures, table_codes, capacity, count, target_value, original_ids, k, a, b, out_ids)
    stats[2] = entries
    stats[3] = capacity
  stats[4] = control[0]
  stats[5] = result
  result

# Sticky-door subset selection: start at the rotating offset, then choose
# nearby/shared-factor terms.  Different offsets still knock on different
# local span doors, while dependent factor spans stay common enough to make
# exact identities plausible.
-> ffsrp_choose_subset(us, vs, ws, rank, k, offset, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank < k || k < 3 || k > 4
    return 0
  selected[0] = offset % rank
  chosen = 1 ## i64
  while chosen < k
    best = 0 - 1 ## i64
    best_score = 0 - 1000000000 ## i64
    scan = 0 ## i64
    while scan < rank
      candidate = (scan + offset + chosen * 17) % rank ## i64
      if ffsr_contains(selected, chosen, candidate) == 0
        score = 0 ## i64
        i = 0 ## i64
        while i < chosen
          other = selected[i] ## i64
          if us[candidate] == us[other]
            score += 12
          if vs[candidate] == vs[other]
            score += 12
          if ws[candidate] == ws[other]
            score += 12
          score -= ffw_popcount(us[candidate] ^ us[other])
          score -= ffw_popcount(vs[candidate] ^ vs[other])
          score -= ffw_popcount(ws[candidate] ^ ws[other])
          i += 1
        if score > best_score
          best = candidate
          best_score = score
      scan += 1
    if best < 0
      return 0
    selected[chosen] = best
    chosen += 1
  chosen

# Target the distance-six "triangle shear" motif found in the real 5x5
# rank-93 scheme.  Two terms share one factor and the XOR of either remaining
# factor equals that factor on a third term.  This condition is only a cheap
# door selector; the complete span join remains the exact admission test.
# At most 4*rank rotating pairs are tried, with one linear third-term scan per
# pair, so this costs O(rank^2) rather than a cubic fleet-side motif sweep.
-> ffsrp_choose_shear_triple(us, vs, ws, rank, offset, selected) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if rank < 3
    return 0
  found = 0 ## i64
  attempt = 0 ## i64
  limit = rank * 4 ## i64
  while attempt < limit && found == 0
    a = (offset + attempt / rank) % rank ## i64
    step = attempt % (rank - 1) ## i64
    b = (a + 1 + step) % rank ## i64
    c = 0 ## i64
    while c < rank && found == 0
      if c != a && c != b
        match = 0 ## i64
        if us[a] == us[b]
          if (vs[a] ^ vs[b]) == vs[c]
            match = 1
          if (ws[a] ^ ws[b]) == ws[c]
            match = 1
        if vs[a] == vs[b]
          if (us[a] ^ us[b]) == us[c]
            match = 1
          if (ws[a] ^ ws[b]) == ws[c]
            match = 1
        if ws[a] == ws[b]
          if (us[a] ^ us[b]) == us[c]
            match = 1
          if (vs[a] ^ vs[b]) == vs[c]
            match = 1
        if match == 1
          selected[0] = a
          selected[1] = b
          selected[2] = c
          found = 3
      c += 1
    attempt += 1
  found

-> ffsrp_in_span3(a, b, c, wanted) (i64 i64 i64 i64) i64
  found = 0 ## i64
  mask = 0 ## i64
  while mask < 8 && found == 0
    value = 0 ## i64
    if (mask & 1) != 0
      value = value ^ a
    if (mask & 2) != 0
      value = value ^ b
    if (mask & 4) != 0
      value = value ^ c
    if value == wanted
      found = 1
    mask += 1
  found

# Pick a window whose three factor spans are guaranteed to contain one live
# term left outside the window.  This is the necessary geometric condition
# for a refactor output to parity-cancel globally.  A bounded deterministic
# pair sample plus complete third-term scan keeps the selector cheap at 7x7.
-> ffsrp_choose_external_span_door(us, vs, ws, rank, k, offset, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank <= k || (k != 3 && k != 4)
    return 0
  anchor = offset % rank ## i64
  found = 0 ## i64
  attempts = 0 ## i64
  limit = rank * 16 ## i64
  rng = (offset + 1) * 6364136223846793005 + 1442695040888963407 ## i64
  while attempts < limit && found == 0
    rng = rng * 6364136223846793005 + 1442695040888963407
    a = (rng ^ (rng >> 29)) & 9223372036854775807 ## i64
    a = a % rank
    rng = rng * 6364136223846793005 + 1442695040888963407
    b = (rng ^ (rng >> 31)) & 9223372036854775807 ## i64
    b = b % rank
    if a != anchor && b != anchor && a != b
      c = 0 ## i64
      while c < rank && found == 0
        if c != anchor && c != a && c != b
          if ffsrp_in_span3(us[a],us[b],us[c],us[anchor]) == 1
            if ffsrp_in_span3(vs[a],vs[b],vs[c],vs[anchor]) == 1
              if ffsrp_in_span3(ws[a],ws[b],ws[c],ws[anchor]) == 1
                selected[0] = a
                selected[1] = b
                selected[2] = c
                found = 3
        c += 1
    attempts += 1
  if found == 3 && k == 4
    d = (anchor + 1) % rank ## i64
    while d == anchor || ffsr_contains(selected,3,d) == 1
      d = (d + 1) % rank
    selected[3] = d
    found = 4
  found

-> ffsrp_search_current_subset(device, library, queue, state, selected, n, k, want, output_path, stats, collision_mode = 0) i64
  si = 0 ## i64
  while si < 6
    stats[si] = 0
    si += 1
  su = i64[4]
  sv = i64[4]
  sw = i64[4]
  if ffsr_capture_current(state, selected, k, su, sv, sw) == 0
    stats[0] = 0 - 1
    return 0
  capacity = ffsr_max_candidates(k) ## i64
  cu = i64[capacity]
  cv = i64[capacity]
  cw = i64[capacity]
  signatures = i64[capacity]
  original_ids = i64[4]
  meta = i64[12]
  count = ffsr_build_candidates(su, sv, sw, k, cu, cv, cw, signatures, original_ids, meta) ## i64
  if count == 0
    stats[0] = 0 - 2
    return 0
  ids = i64[4]
  external_u = i64[state[4]]
  external_v = i64[state[4]]
  external_w = i64[state[4]]
  external_count = 0 ## i64
  position = 0 ## i64
  while position < state[6]
    if ffsr_position_selected(selected,k,position) == 0
      slot = state[state[50]+position] ## i64
      external_u[external_count] = state[state[44]+slot]
      external_v[external_count] = state[state[45]+slot]
      external_w[external_count] = state[state[46]+slot]
      external_count += 1
    position += 1
  collision_stats = i64[4]
  found = 0 ## i64
  if collision_mode >= 0
    found = ffsrp_find_collision_ids(cu,cv,cw,signatures,count,meta[5],original_ids,k,want,external_u,external_v,external_w,external_count,ids,collision_stats)
  if found == want
    stats[0] = count
    stats[1] = collision_stats[1]
    stats[4] = 0 - 1
    stats[5] = found
  if found != want && collision_mode > 0
    return 0
  if found != want && collision_mode <= 0
    found = ffsrp_find_ids_gpu(device, library, queue, signatures, count, meta[5], original_ids, k, want, ids, stats)
  if found != want
    return 0
  out_u = i64[4]
  out_v = i64[4]
  out_w = i64[4]
  made = ffsr_materialize_ids(cu, cv, cw, count, ids, found, out_u, out_v, out_w) ## i64
  if made != found
    return 0
  if ffsr_verify_local_replacement(su, sv, sw, k, out_u, out_v, out_w, made) == 0
    return 0
  # The compact splice treats external term matches as the legal GF(2)
  # cancellations they are and performs the full n^6 pre/post verification.
  # Only a verified state is serialized.
  rank = ffsr_apply_current_compact(state, selected, k, out_u, out_v, out_w, made) ## i64
  if rank < 1 || ffw_verify_current_exact(state, n) == 0
    return 0
  written = ffw_dump_current(state, output_path) ## i64
  if written != rank
    return 0
  rank

-> ffsrp_search(seed_path, output_path, n, k, want, subsets, offset, metal_path, metallib_path = "", collision_only = 0) i64
  if n < 2 || n > 7 || ffsr_move_supported(k, want) == 0
    return 0 - 1
  if subsets < 1 || subsets > 8 || offset < 0
    return 0 - 1
  if k == 4 && subsets != 1
    return 0 - 1
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, seed_path, n, capacity, 91009 + offset, 0, 1, 1, 1) ## i64
  if rank < k || ffw_verify_current_exact(state, n) == 0
    return 0 - 2
  device = metal_device()
  library = nil
  queue = nil
  if collision_only == 0
    if metallib_path != ""
      library = metal_load_library(device, metallib_path)
    if library == nil
      msl = read_file(metal_path)
      if msl == nil
        return 0 - 3
      library = metal_compile_source(device, msl)
    queue = metal_queue(device)
  cleared = write_file(output_path, "")
  if cleared == false
    return 0 - 4
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_current(state, us, vs, ws) ## i64
  # First inspect every scheduled neighborhood for parity-canceling outputs.
  # Only after that pass may an ordinary noncollision refactor terminate the
  # child, otherwise the first generic hit starves later rank-drop doors.
  phase = 0 ## i64
  phase_limit = 2 ## i64
  if collision_only != 0
    phase_limit = 1
  while phase < phase_limit
    s = 0 ## i64
    while s < subsets
      selected = i64[4]
      chosen = 0 ## i64
      door_offset = offset + s * 37 ## i64
      # Equal-rank motif/generic pairs inspect the same anchor, measuring the
      # selector rather than silently changing both selector and neighborhood.
      if k == 3 && want == 3
        door_offset = offset + (s / 2) * 37
      # Interleave generic sticky doors with the real triangle-shear motif.
      use_shear = 0 ## i64
      if k == 3 && ((offset + s) & 1) != 0
        use_shear = 1
      # Equal-rank epochs are where the distance-six triangle family is most
      # valuable.  Start them on a motif door, then alternate if batched.
      if k == 3 && want == 3 && (s & 1) == 0
        use_shear = 1
      # Every third neighborhood is collision-directed: its selected factor
      # spans deliberately contain one external live term.
      if (s % 3) == 2 || (k == 4 && (offset % 3) == 2)
        chosen = ffsrp_choose_external_span_door(us,vs,ws,exported,k,door_offset,selected)
      if chosen != k && use_shear == 1
        chosen = ffsrp_choose_shear_triple(us, vs, ws, exported, door_offset, selected)
      if chosen != k
        chosen = ffsrp_choose_subset(us, vs, ws, exported, k, door_offset, selected)
      if chosen == k
        stats = i64[6]
        mode = 1 ## i64
        if phase == 1
          mode = 0 - 1
        hit = ffsrp_search_current_subset(device, library, queue, state, selected, n, k, want, output_path, stats, mode) ## i64
        if hit > 0
          compact = 0 ## i64
          if stats[4] < 0
            compact = 1
          << "GPU_POOL_SPAN n=" + n.to_s() + " k=" + k.to_s() + " want=" + want.to_s() + " candidates=" + stats[0].to_s() + " table=" + stats[3].to_s() + " compact=" + compact.to_s() + " hit=1 rank=" + hit.to_s()
          return hit
      s += 1
    phase += 1
  << "GPU_POOL_SPAN n=" + n.to_s() + " k=" + k.to_s() + " want=" + want.to_s() + " subsets=" + subsets.to_s() + " hit=0"
  0
