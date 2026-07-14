# Generalized exact GPU XOR surgery for rotating FlipFleet pool modes.
# Searches 6->5 (pair + triple) and 7->6 (triple + triple) replacements.

## u32[]: fps0, fps1, fps2, fps3, triple0, triple1, triple2, triple3, packed
## i32[]: params
@gpu fn ffx_enumerate_triples(fps0, fps1, fps2, fps3, triple0, triple1, triple2, triple3, packed, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  square = count * count ## i32
  a = tid / square ## i32
  rem = tid - a * square ## i32
  b = rem / count ## i32
  c = rem - b * count ## i32
  packed[tid] = 0
  if a < b
    if b < c
      triple0[tid] = fps0[a] ^ fps0[b] ^ fps0[c]
      triple1[tid] = fps1[a] ^ fps1[b] ^ fps1[c]
      triple2[tid] = fps2[a] ^ fps2[b] ^ fps2[c]
      triple3[tid] = fps3[a] ^ fps3[b] ^ fps3[c]
      packed[tid] = tid + 1

# Regular count^4 enumeration is intentionally kept on Metal.  The campaign
# caps the 8->7/9->8 candidate family at 16 terms, so this is at most 65,536
# threads and the host only sees the C(count,4) canonical tuples.
## u32[]: fps0, fps1, fps2, fps3, quad0, quad1, quad2, quad3, packed
## i32[]: params
@gpu fn ffx_enumerate_quads(fps0, fps1, fps2, fps3, quad0, quad1, quad2, quad3, packed, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  square = count * count ## i32
  cube = square * count ## i32
  a = tid / cube ## i32
  rem = tid - a * cube ## i32
  b = rem / square ## i32
  rem = rem - b * square
  c = rem / count ## i32
  d = rem - c * count ## i32
  packed[tid] = 0
  if a < b
    if b < c
      if c < d
        quad0[tid] = fps0[a] ^ fps0[b] ^ fps0[c] ^ fps0[d]
        quad1[tid] = fps1[a] ^ fps1[b] ^ fps1[c] ^ fps1[d]
        quad2[tid] = fps2[a] ^ fps2[b] ^ fps2[c] ^ fps2[d]
        quad3[tid] = fps3[a] ^ fps3[b] ^ fps3[c] ^ fps3[d]
        packed[tid] = tid + 1

## u32[]: fps0, fps1, fps2, fps3, table, target, matches
## i32[]: params
@gpu fn ffx_probe_triples(fps0, fps1, fps2, fps3, table, target, matches, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## u32
  table_cap = params[2] ## i32
  tuple_size = params[3] ## i32
  square = count * count ## i32
  a = tid / square ## i32
  rem = tid - a * square ## i32
  b = rem / count ## i32
  c = rem - b * count ## i32
  matches[tid] = 0
  if a < b
    if b < c
      want0 = target[0] ^ fps0[a] ^ fps0[b] ^ fps0[c] ## u32
      want1 = target[1] ^ fps1[a] ^ fps1[b] ^ fps1[c] ## u32
      want2 = target[2] ^ fps2[a] ^ fps2[b] ^ fps2[c] ## u32
      want3 = target[3] ^ fps3[a] ^ fps3[b] ^ fps3[c] ## u32
      mixed = want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19) ## u32
      slot = mixed & table_mask ## u32
      used_offset = table_cap * 4 ## i32
      tuple_offset = table_cap * 5 ## i32
      scanned = 0 ## i32
      found = 0 ## i32
      while scanned < table_cap
        if table[used_offset + slot] == 0
          scanned = table_cap
        else
          if table[slot] == want0
            if table[table_cap + slot] == want1
              if table[table_cap * 2 + slot] == want2
                if table[table_cap * 3 + slot] == want3
                  code = table[tuple_offset + slot] - 1 ## u32
                  x = 0 ## i32
                  y = 0 ## i32
                  z = -1 ## i32
                  if tuple_size == 2
                    x = code / count
                    y = code - x * count
                  if tuple_size == 3
                    x = code / square
                    rest = code - x * square ## i32
                    y = rest / count
                    z = rest - y * count
                  overlap = 0 ## i32
                  if x == a
                    overlap = 1
                  if x == b
                    overlap = 1
                  if x == c
                    overlap = 1
                  if y == a
                    overlap = 1
                  if y == b
                    overlap = 1
                  if y == c
                    overlap = 1
                  if z == a
                    overlap = 1
                  if z == b
                    overlap = 1
                  if z == c
                    overlap = 1
                  if overlap == 0
                    matches[tid] = table[tuple_offset + slot]
                    found = 1
                    scanned = table_cap
          if found == 0
            slot = (slot + 1) & table_mask
            scanned = scanned + 1

## u32[]: fps0, fps1, fps2, fps3, table, target, matches
## i32[]: params
@gpu fn ffx_probe_quads(fps0, fps1, fps2, fps3, table, target, matches, params)
  tid = gpu.thread_position_in_grid.x ## i32
  count = params[0] ## i32
  table_mask = params[1] ## u32
  table_cap = params[2] ## i32
  tuple_size = params[3] ## i32
  square = count * count ## i32
  cube = square * count ## i32
  a = tid / cube ## i32
  rem = tid - a * cube ## i32
  b = rem / square ## i32
  rem = rem - b * square
  c = rem / count ## i32
  d = rem - c * count ## i32
  matches[tid] = 0
  if a < b
    if b < c
      if c < d
        want0 = target[0] ^ fps0[a] ^ fps0[b] ^ fps0[c] ^ fps0[d] ## u32
        want1 = target[1] ^ fps1[a] ^ fps1[b] ^ fps1[c] ^ fps1[d] ## u32
        want2 = target[2] ^ fps2[a] ^ fps2[b] ^ fps2[c] ^ fps2[d] ## u32
        want3 = target[3] ^ fps3[a] ^ fps3[b] ^ fps3[c] ^ fps3[d] ## u32
        mixed = want0 ^ (want1 >> 7) ^ (want2 >> 13) ^ (want3 >> 19) ## u32
        slot = mixed & table_mask ## u32
        used_offset = table_cap * 4 ## i32
        tuple_offset = table_cap * 5 ## i32
        scanned = 0 ## i32
        found = 0 ## i32
        while scanned < table_cap
          if table[used_offset + slot] == 0
            scanned = table_cap
          else
            if table[slot] == want0
              if table[table_cap + slot] == want1
                if table[table_cap * 2 + slot] == want2
                  if table[table_cap * 3 + slot] == want3
                    code = table[tuple_offset + slot] - 1 ## u32
                    x = code / cube ## i32
                    rest = code - x * cube ## i32
                    y = rest / square ## i32
                    rest = rest - y * square
                    z = rest / count ## i32
                    q = rest - z * count ## i32
                    overlap = 0 ## i32
                    if x == a
                      overlap = 1
                    if x == b
                      overlap = 1
                    if x == c
                      overlap = 1
                    if x == d
                      overlap = 1
                    if y == a
                      overlap = 1
                    if y == b
                      overlap = 1
                    if y == c
                      overlap = 1
                    if y == d
                      overlap = 1
                    if z == a
                      overlap = 1
                    if z == b
                      overlap = 1
                    if z == c
                      overlap = 1
                    if z == d
                      overlap = 1
                    if q == a
                      overlap = 1
                    if q == b
                      overlap = 1
                    if q == c
                      overlap = 1
                    if q == d
                      overlap = 1
                    if overlap == 0
                      matches[tid] = table[tuple_offset + slot]
                      found = 1
                      scanned = table_cap
            if found == 0
              slot = (slot + 1) & table_mask
              scanned = scanned + 1

use core/metal
use metaflip_worker
use flipfleet_mitm_lane_lib

-> ffx_choose_subset(us, vs, ws, rank, k, offset, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  selected[0] = offset % rank
  count = 1 ## i64
  while count < k
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    candidate = 0 ## i64
    while candidate < rank
      if ffm_selected_index(selected, count, candidate) == 0
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
        if score > best_score || best < 0
          best = candidate
          best_score = score
      candidate += 1
    if best < 0
      return 0
    selected[count] = best
    count += 1
  count

-> ffx_axis_pool(us, vs, ws, rank, selected, selected_count, axis, nearby, values) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < selected_count
    value = ffm_axis_value(us, vs, ws, selected[i], axis) ## i64
    count = ffm_add_unique(values, count, 64, value)
    i += 1
  left = 0 ## i64
  while left < selected_count
    right = left + 1 ## i64
    while right < selected_count
      value = ffm_axis_value(us, vs, ws, selected[left], axis) ^ ffm_axis_value(us, vs, ws, selected[right], axis) ## i64
      count = ffm_add_unique(values, count, 64, value)
      right += 1
    left += 1
  # Add globally closest live factors.
  added = 0 ## i64
  while added < nearby
    best_index = 0 - 1 ## i64
    best_distance = 999999999 ## i64
    i = 0
    while i < rank
      value = ffm_axis_value(us, vs, ws, i, axis) ## i64
      if ffm_contains(values, count, value) == 0
        distance = 999999999 ## i64
        j = 0 ## i64
        while j < selected_count
          d = ffw_popcount(value ^ ffm_axis_value(us, vs, ws, selected[j], axis)) ## i64
          if d < distance
            distance = d
          j += 1
        if distance < best_distance
          best_distance = distance
          best_index = i
      i += 1
    if best_index >= 0
      count = ffm_add_unique(values, count, 64, ffm_axis_value(us, vs, ws, best_index, axis))
    added += 1
  count

-> ffx_candidates(us, vs, ws, rank, selected, selected_count, limit, nearby, cu, cv, cw) (i64[] i64[] i64[] i64 i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  pu = i64[64]
  pv = i64[64]
  pw = i64[64]
  nu = ffx_axis_pool(us, vs, ws, rank, selected, selected_count, 0, nearby, pu) ## i64
  nv = ffx_axis_pool(us, vs, ws, rank, selected, selected_count, 1, nearby, pv) ## i64
  nw = ffx_axis_pool(us, vs, ws, rank, selected, selected_count, 2, nearby, pw) ## i64
  count = 0 ## i64
  i = 0 ## i64
  while i < selected_count && count < limit
    source = selected[i] ## i64
    if ffm_candidate_present(cu, cv, cw, count, us[source], vs[source], ws[source]) == 0
      cu[count] = us[source]
      cv[count] = vs[source]
      cw[count] = ws[source]
      count += 1
    i += 1
  # Reconstructed parents of selected split pairs are the most important
  # surgery candidates; protect them ahead of the bounded Cartesian tail.
  left = 0 ## i64
  while left < selected_count && count < limit
    right = left + 1 ## i64
    while right < selected_count && count < limit
      li = selected[left] ## i64
      ri = selected[right] ## i64
      candidate_u = 0 ## i64
      candidate_v = 0 ## i64
      candidate_w = 0 ## i64
      if vs[li] == vs[ri] && ws[li] == ws[ri]
        candidate_u = us[li] ^ us[ri]
        candidate_v = vs[li]
        candidate_w = ws[li]
      if us[li] == us[ri] && ws[li] == ws[ri]
        candidate_u = us[li]
        candidate_v = vs[li] ^ vs[ri]
        candidate_w = ws[li]
      if us[li] == us[ri] && vs[li] == vs[ri]
        candidate_u = us[li]
        candidate_v = vs[li]
        candidate_w = ws[li] ^ ws[ri]
      if candidate_u != 0 && candidate_v != 0 && candidate_w != 0
        if ffm_candidate_present(cu, cv, cw, count, candidate_u, candidate_v, candidate_w) == 0
          cu[count] = candidate_u
          cv[count] = candidate_v
          cw[count] = candidate_w
          count += 1
      right += 1
    left += 1
  a = 0 ## i64
  while a < nu && count < limit
    b = 0 ## i64
    while b < nv && count < limit
      c = 0 ## i64
      while c < nw && count < limit
        if pu[a] != 0 && pv[b] != 0 && pw[c] != 0
          if ffm_candidate_present(cu, cv, cw, count, pu[a], pv[b], pw[c]) == 0
            cu[count] = pu[a]
            cv[count] = pv[b]
            cw[count] = pw[c]
            count += 1
        c += 1
      b += 1
    a += 1
  count

-> ffx_target_fingerprint(us, vs, ws, selected, selected_count, dim, out) (i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
  out[0] = 0
  out[1] = 0
  out[2] = 0
  out[3] = 0
  words = i64[4]
  i = 0 ## i64
  while i < selected_count
    source = selected[i] ## i64
    z = ffm_fingerprint(us[source], vs[source], ws[source], dim, words) ## i64
    j = 0 ## i64
    while j < 4
      out[j] = out[j] ^ words[j]
      j += 1
    i += 1
  1

-> ffx_local_exact(us, vs, ws, selected, selected_count, cu, cv, cw, indices, replacement_count, n) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64) i64
  dim = n * n ## i64
  ok = 1 ## i64
  ai = 0 ## i64
  while ai < dim && ok == 1
    bi = 0 ## i64
    while bi < dim && ok == 1
      ci = 0 ## i64
      while ci < dim && ok == 1
        parity = 0 ## i64
        t = 0 ## i64
        while t < selected_count
          source = selected[t] ## i64
          if ((us[source] >> ai) & 1) == 1 && ((vs[source] >> bi) & 1) == 1 && ((ws[source] >> ci) & 1) == 1
            parity = parity ^ 1
          t += 1
        t = 0
        while t < replacement_count
          source = indices[t] ## i64
          if ((cu[source] >> ai) & 1) == 1 && ((cv[source] >> bi) & 1) == 1 && ((cw[source] >> ci) & 1) == 1
            parity = parity ^ 1
          t += 1
        if parity != 0
          ok = 0
        ci += 1
      bi += 1
    ai += 1
  ok

-> ffx_accept(us, vs, ws, rank, selected, selected_count, cu, cv, cw, indices, replacement_count, n, output_path) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[] i64 i64 String) i64
  cap = ffw_default_capacity(n) ## i64
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  out_rank = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffm_selected_index(selected, selected_count, i) == 0
      outu[out_rank] = us[i]
      outv[out_rank] = vs[i]
      outw[out_rank] = ws[i]
      out_rank += 1
    i += 1
  i = 0
  while i < replacement_count && out_rank > 0
    source = indices[i] ## i64
    out_rank = ffm_toggle_plain(outu, outv, outw, out_rank, cap, cu[source], cv[source], cw[source])
    i += 1
  if out_rank >= rank || out_rank < 1
    return 0
  state = i64[ffw_state_size(cap)]
  loaded = ffw_init_terms_cap(state, outu, outv, outw, out_rank, n, cap, 81001, 0, 1, 1, 1) ## i64
  if loaded != out_rank || ffw_verify_best_exact(state, n) != 1
    return 0
  ffw_dump_best(state, output_path)

# The hash table is a shared u32 Metal array. Keeping this annotation exact is
# important: an i64[] annotation makes host indexing stride by eight bytes and
# can walk beyond the mmap even though the GPU sees a packed uint buffer.
-> ffx_insert(table, hcap, p0, p1, p2, p3, tuple_code) (u32[] i64 i64 i64 i64 i64 i64) i64
  mixed = p0 ^ (p1 >> 7) ^ (p2 >> 13) ^ (p3 >> 19) ## i64
  slot = mixed & (hcap - 1) ## i64
  used_offset = hcap * 4 ## i64
  tuple_offset = hcap * 5 ## i64
  while table[used_offset + slot] != 0
    slot = (slot + 1) & (hcap - 1)
  table[used_offset + slot] = 1
  table[slot] = p0
  table[hcap + slot] = p1
  table[hcap * 2 + slot] = p2
  table[hcap * 3 + slot] = p3
  table[tuple_offset + slot] = tuple_code
  1

-> ffx_search_subset(device, library, queue, us, vs, ws, rank, selected, k, cu, cv, cw, count, n, output_path) i64
  fps0 = metal_array(32, count)
  fps1 = metal_array(32, count)
  fps2 = metal_array(32, count)
  fps3 = metal_array(32, count)
  words = i64[4]
  i = 0 ## i64
  while i < count
    z = ffm_fingerprint(cu[i], cv[i], cw[i], n * n, words) ## i64
    fps0[i] = words[0]
    fps1[i] = words[1]
    fps2[i] = words[2]
    fps3[i] = words[3]
    i += 1
  target = metal_array(32, 4)
  target_words = i64[4]
  z = ffx_target_fingerprint(us, vs, ws, selected, k, n * n, target_words) ## i64
  i = 0
  while i < 4
    target[i] = target_words[i]
    i += 1
  square = count * count ## i64
  cube = square * count ## i64
  fourth = cube * count ## i64
  table_tuple_size = 2 ## i64
  query_tuple_size = 3 ## i64
  entries = count * (count - 1) / 2 ## i64
  if k == 7 || k == 8
    table_tuple_size = 3
    entries = count * (count - 1) * (count - 2) / 6
  if k == 8 || k == 9
    query_tuple_size = 4
  if k == 9
    table_tuple_size = 4
    entries = count * (count - 1) * (count - 2) * (count - 3) / 24
  hcap = 1 ## i64
  while hcap < entries * 3
    hcap *= 2
  table = metal_array(32, hcap * 6)
  if table_tuple_size == 2
    a = 0 ## i64
    while a < count
      b = a + 1 ## i64
      while b < count
        code = a * count + b + 1 ## i64
        z = ffx_insert(table, hcap, fps0[a] ^ fps0[b], fps1[a] ^ fps1[b], fps2[a] ^ fps2[b], fps3[a] ^ fps3[b], code)
        b += 1
      a += 1
  if table_tuple_size == 3
    triple0 = metal_array(32, cube)
    triple1 = metal_array(32, cube)
    triple2 = metal_array(32, cube)
    triple3 = metal_array(32, cube)
    packed = metal_array(32, cube)
    enum_params = metal_array(32, 1)
    enum_params[0] = count
    enum_pipeline = metal_pipeline(library, "ffx_enumerate_triples")
    metal_dispatch_n(queue, enum_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple0), metal_buffer_for(device, triple1), metal_buffer_for(device, triple2), metal_buffer_for(device, triple3), metal_buffer_for(device, packed), metal_buffer_for(device, enum_params)], cube)
    index = 0 ## i64
    while index < cube
      if packed[index] != 0
        z = ffx_insert(table, hcap, triple0[index], triple1[index], triple2[index], triple3[index], packed[index])
      index += 1
  if table_tuple_size == 4
    quad0 = metal_array(32, fourth)
    quad1 = metal_array(32, fourth)
    quad2 = metal_array(32, fourth)
    quad3 = metal_array(32, fourth)
    packed4 = metal_array(32, fourth)
    enum4_params = metal_array(32, 1)
    enum4_params[0] = count
    enum4_pipeline = metal_pipeline(library, "ffx_enumerate_quads")
    metal_dispatch_n(queue, enum4_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, quad0), metal_buffer_for(device, quad1), metal_buffer_for(device, quad2), metal_buffer_for(device, quad3), metal_buffer_for(device, packed4), metal_buffer_for(device, enum4_params)], fourth)
    index = 0
    while index < fourth
      if packed4[index] != 0
        z = ffx_insert(table, hcap, quad0[index], quad1[index], quad2[index], quad3[index], packed4[index])
      index += 1
  query_work = cube ## i64
  if query_tuple_size == 4
    query_work = fourth
  matches = metal_array(32, query_work)
  probe_params = metal_array(32, 4)
  probe_params[0] = count
  probe_params[1] = hcap - 1
  probe_params[2] = hcap
  probe_params[3] = table_tuple_size
  if query_tuple_size == 3
    probe_pipeline = metal_pipeline(library, "ffx_probe_triples")
    metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, table), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, probe_params)], cube)
  if query_tuple_size == 4
    probe_pipeline = metal_pipeline(library, "ffx_probe_quads")
    metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, table), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, probe_params)], fourth)
  replacement_count = k - 1 ## i64
  indices = i64[8]
  index = 0
  while index < query_work
    packed_table = matches[index] ## i64
    if packed_table > 0
      code = packed_table - 1 ## i64
      if table_tuple_size == 2
        indices[0] = code / count
        indices[1] = code % count
      if table_tuple_size == 3
        indices[0] = code / square
        rem2 = code - indices[0] * square ## i64
        indices[1] = rem2 / count
        indices[2] = rem2 % count
      if table_tuple_size == 4
        indices[0] = code / cube
        rem2 = code - indices[0] * cube ## i64
        indices[1] = rem2 / square
        rem2 = rem2 - indices[1] * square
        indices[2] = rem2 / count
        indices[3] = rem2 % count
      query_offset = table_tuple_size ## i64
      if query_tuple_size == 3
        qa = index / square ## i64
        qrem = index - qa * square ## i64
        qb = qrem / count ## i64
        qc = qrem - qb * count ## i64
        indices[query_offset] = qa
        indices[query_offset + 1] = qb
        indices[query_offset + 2] = qc
      if query_tuple_size == 4
        qa = index / cube
        qrem = index - qa * cube
        qb = qrem / square
        qrem = qrem - qb * square
        qc = qrem / count
        qd = qrem - qc * count ## i64
        indices[query_offset] = qa
        indices[query_offset + 1] = qb
        indices[query_offset + 2] = qc
        indices[query_offset + 3] = qd
      if ffx_local_exact(us, vs, ws, selected, k, cu, cv, cw, indices, replacement_count, n) == 1
        hit = ffx_accept(us, vs, ws, rank, selected, k, cu, cv, cw, indices, replacement_count, n, output_path) ## i64
        if hit > 0
          return hit
    index += 1
  0

# Exhaustive tensor gate for one subset of candidate indices.  This is used
# only after a 128-bit GPU join reports a possible zero circuit, so the n^6
# reconstruction is rare and fingerprint collisions cannot create outputs.
-> ffx_zero_mask(cu, cv, cw, indices, count, mask, n) (i64[] i64[] i64[] i64[] i64 i64 i64) i64
  dim = n * n ## i64
  ok = 1 ## i64
  ai = 0 ## i64
  while ai < dim && ok == 1
    bi = 0 ## i64
    while bi < dim && ok == 1
      ci = 0 ## i64
      while ci < dim && ok == 1
        parity = 0 ## i64
        t = 0 ## i64
        while t < count
          if ((mask >> t) & 1) == 1
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

# A circuit must be a zero set with no nonempty proper zero subset.  The GPU
# join gives distinct indices; this exact proper-subset check is therefore a
# complete primitivity test for the five- and six-term modes.
-> ffx_primitive_zero(cu, cv, cw, indices, count, n) (i64[] i64[] i64[] i64[] i64 i64) i64
  full = (1 << count) - 1 ## i64
  if ffx_zero_mask(cu, cv, cw, indices, count, full, n) == 0
    return 0
  subset = 1 ## i64
  while subset < full
    if ffx_zero_mask(cu, cv, cw, indices, count, subset, n) == 1
      return 0
    subset += 1
  1

-> ffx_accept_identity(us, vs, ws, rank, cu, cv, cw, indices, identity_count, n, output_path) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 String) i64
  cap = ffw_default_capacity(n) ## i64
  outu = i64[cap]
  outv = i64[cap]
  outw = i64[cap]
  i = 0 ## i64
  while i < rank
    outu[i] = us[i]
    outv[i] = vs[i]
    outw[i] = ws[i]
    i += 1
  out_rank = rank ## i64
  i = 0
  while i < identity_count && out_rank > 0
    source = indices[i] ## i64
    out_rank = ffm_toggle_plain(outu, outv, outw, out_rank, cap, cu[source], cv[source], cw[source])
    i += 1
  if out_rank < 1
    return 0
  state = i64[ffw_state_size(cap)]
  loaded = ffw_init_terms_cap(state, outu, outv, outw, out_rank, n, cap, 85009, 0, 1, 1, 1) ## i64
  if loaded != out_rank || ffw_verify_best_exact(state, n) != 1
    return 0
  ffw_dump_best(state, output_path)

# Mine a primitive 5- or 6-term zero circuit with a GPU pair/triple join and
# toggle it into the live scheme.  This is an escape constructor, not a rank
# proof: the result may sit above, at, or below the input rank, but it is always
# independently reconstructed before serialization.
-> ffx_search_zero_join(device, library, queue, us, vs, ws, rank, cu, cv, cw, count, identity_count, n, output_path) i64
  fps0 = metal_array(32, count)
  fps1 = metal_array(32, count)
  fps2 = metal_array(32, count)
  fps3 = metal_array(32, count)
  words = i64[4]
  i = 0 ## i64
  while i < count
    z = ffm_fingerprint(cu[i], cv[i], cw[i], n * n, words) ## i64
    fps0[i] = words[0]
    fps1[i] = words[1]
    fps2[i] = words[2]
    fps3[i] = words[3]
    i += 1
  target = metal_array(32, 4)
  i = 0
  while i < 4
    target[i] = 0
    i += 1
  square = count * count ## i64
  cube = square * count ## i64
  table_tuple_size = identity_count - 3 ## i64
  entries = count * (count - 1) / 2 ## i64
  if table_tuple_size == 3
    entries = count * (count - 1) * (count - 2) / 6
  hcap = 1 ## i64
  while hcap < entries * 3
    hcap *= 2
  table = metal_array(32, hcap * 6)
  if table_tuple_size == 2
    a = 0 ## i64
    while a < count
      b = a + 1 ## i64
      while b < count
        code = a * count + b + 1 ## i64
        z = ffx_insert(table, hcap, fps0[a] ^ fps0[b], fps1[a] ^ fps1[b], fps2[a] ^ fps2[b], fps3[a] ^ fps3[b], code)
        b += 1
      a += 1
  if table_tuple_size == 3
    triple0 = metal_array(32, cube)
    triple1 = metal_array(32, cube)
    triple2 = metal_array(32, cube)
    triple3 = metal_array(32, cube)
    packed = metal_array(32, cube)
    enum_params = metal_array(32, 1)
    enum_params[0] = count
    enum_pipeline = metal_pipeline(library, "ffx_enumerate_triples")
    metal_dispatch_n(queue, enum_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, triple0), metal_buffer_for(device, triple1), metal_buffer_for(device, triple2), metal_buffer_for(device, triple3), metal_buffer_for(device, packed), metal_buffer_for(device, enum_params)], cube)
    index = 0 ## i64
    while index < cube
      if packed[index] != 0
        z = ffx_insert(table, hcap, triple0[index], triple1[index], triple2[index], triple3[index], packed[index])
      index += 1
  matches = metal_array(32, cube)
  probe_params = metal_array(32, 4)
  probe_params[0] = count
  probe_params[1] = hcap - 1
  probe_params[2] = hcap
  probe_params[3] = table_tuple_size
  probe_pipeline = metal_pipeline(library, "ffx_probe_triples")
  metal_dispatch_n(queue, probe_pipeline, [metal_buffer_for(device, fps0), metal_buffer_for(device, fps1), metal_buffer_for(device, fps2), metal_buffer_for(device, fps3), metal_buffer_for(device, table), metal_buffer_for(device, target), metal_buffer_for(device, matches), metal_buffer_for(device, probe_params)], cube)
  indices = i64[6]
  index = 0
  while index < cube
    packed_table = matches[index] ## i64
    if packed_table > 0
      code = packed_table - 1 ## i64
      if table_tuple_size == 2
        indices[0] = code / count
        indices[1] = code % count
      if table_tuple_size == 3
        indices[0] = code / square
        rem2 = code - indices[0] * square ## i64
        indices[1] = rem2 / count
        indices[2] = rem2 % count
      qa = index / square ## i64
      qrem = index - qa * square ## i64
      qb = qrem / count ## i64
      qc = qrem - qb * count ## i64
      indices[table_tuple_size] = qa
      indices[table_tuple_size + 1] = qb
      indices[table_tuple_size + 2] = qc
      if ffx_primitive_zero(cu, cv, cw, indices, identity_count, n) == 1
        hit = ffx_accept_identity(us, vs, ws, rank, cu, cv, cw, indices, identity_count, n, output_path) ## i64
        if hit > 0
          return hit
    index += 1
  0

-> ffx_mine_circuits(seed_path, output_path, n, subsets, pool, nearby, offset, metal_path, metallib_path = "") i64
  if n < 3 || n > 7 || pool < 6
    return 0 - 1
  cap = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(cap)]
  rank = ffw_load_scheme_cap(state, seed_path, n, cap, 87011 + offset, 0, 1, 1, 1) ## i64
  if rank < 5 || ffw_verify_best_exact(state, n) != 1
    return 0 - 2
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  z = ffw_export_best(state, us, vs, ws) ## i64
  device = metal_device()
  library = nil
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
  s = 0 ## i64
  while s < subsets
    identity_count = 5 + ((offset + s) & 1) ## i64
    if rank >= identity_count
      selected = i64[6]
      chosen = ffx_choose_subset(us, vs, ws, rank, identity_count, offset + s * 17, selected) ## i64
      if chosen == identity_count
        cu = i64[pool]
        cv = i64[pool]
        cw = i64[pool]
        count = ffx_candidates(us, vs, ws, rank, selected, identity_count, pool, nearby, cu, cv, cw) ## i64
        hit = ffx_search_zero_join(device, library, queue, us, vs, ws, rank, cu, cv, cw, count, identity_count, n, output_path) ## i64
        if hit > 0
          << "GPU_POOL_CIRCUIT n=" + n.to_s() + " terms=" + identity_count.to_s() + " pool=" + count.to_s() + " hit=1 rank=" + hit.to_s()
          return hit
    s += 1
  << "GPU_POOL_CIRCUIT n=" + n.to_s() + " terms=5+ subsets=" + subsets.to_s() + " pool=" + pool.to_s() + " hit=0"
  0

-> ffx_search(seed_path, output_path, n, k, subsets, pool, nearby, offset, metal_path, metallib_path = "") i64
  if k == 5
    return ffx_mine_circuits(seed_path, output_path, n, subsets, pool, nearby, offset, metal_path, metallib_path)
  if k < 6 || k > 9 || n < 3 || n > 7
    return 0 - 1
  cap = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(cap)]
  rank = ffw_load_scheme_cap(state, seed_path, n, cap, 83001 + offset, 0, 1, 1, 1) ## i64
  if rank < k || ffw_verify_best_exact(state, n) != 1
    return 0 - 2
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  z = ffw_export_best(state, us, vs, ws) ## i64
  device = metal_device()
  library = nil
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
  s = 0 ## i64
  while s < subsets
    selected = i64[9]
    chosen = ffx_choose_subset(us, vs, ws, rank, k, offset + s * 17, selected) ## i64
    if chosen == k
      cu = i64[pool]
      cv = i64[pool]
      cw = i64[pool]
      count = ffx_candidates(us, vs, ws, rank, selected, k, pool, nearby, cu, cv, cw) ## i64
      hit = ffx_search_subset(device, library, queue, us, vs, ws, rank, selected, k, cu, cv, cw, count, n, output_path) ## i64
      if hit > 0
        << "GPU_POOL_KXOR n=" + n.to_s() + " k=" + k.to_s() + " pool=" + count.to_s() + " hit=1 rank=" + hit.to_s()
        return hit
    s += 1
  << "GPU_POOL_KXOR n=" + n.to_s() + " k=" + k.to_s() + " subsets=" + subsets.to_s() + " pool=" + pool.to_s() + " hit=0"
  0
