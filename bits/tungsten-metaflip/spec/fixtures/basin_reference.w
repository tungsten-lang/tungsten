use ../../lib/metaflip/fleet/basin_stats

# Frozen pre-optimization oracle: deliberately retain scalar bit loops.
-> ffbr_reverse_factor(mask, n) (i64 i64) i64
  result = 0 ## i64
  row = 0 ## i64
  while row < n
    col = 0 ## i64
    while col < n
      source = row * n + col ## i64
      if ((mask >> source) & 1) == 1
        target = (n - 1 - row) * n + (n - 1 - col) ## i64
        result = result | (1 << target)
      col += 1
    row += 1
  result

-> ffbr_transform_factor(u, v, w, n, code, reverse, axis) (i64 i64 i64 i64 i64 i64 i64) i64
  result = u ## i64
  if code == 0
    if axis == 1
      result = v
    if axis == 2
      result = w
  if code == 1
    result = v
    if axis == 1
      result = ffe_transpose(w, n)
    if axis == 2
      result = ffe_transpose(u, n)
  if code == 2
    result = ffe_transpose(w, n)
    if axis == 1
      result = u
    if axis == 2
      result = ffe_transpose(v, n)
  if code == 3
    result = ffe_transpose(v, n)
    if axis == 1
      result = ffe_transpose(u, n)
    if axis == 2
      result = ffe_transpose(w, n)
  if code == 4
    result = ffe_transpose(u, n)
    if axis == 1
      result = w
    if axis == 2
      result = v
  if code == 5
    result = w
    if axis == 1
      result = ffe_transpose(v, n)
    if axis == 2
      result = u
  if reverse != 0
    result = ffbr_reverse_factor(result, n)
  result

-> ffbr_identity_view(state, current) (i64[] i64) i64
  rank = ffbi_view_rank(state, current) ## i64
  if rank < 1
    return 0
  n = ffw_n(state) ## i64
  gl = ffbi_gl_invariant_view(state, current) ## i64
  minimum = 9223372036854775807 ## i64
  reverse = 0 ## i64
  while reverse < 2
    code = 0 ## i64
    while code < 6
      sum1 = 0 ## i64
      square1 = 0 ## i64
      sum2 = 0 ## i64
      square2 = 0 ## i64
      bits = 0 ## i64
      i = 0 ## i64
      while i < rank
        source_u = ffbi_view_u(state, i, current) ## i64
        source_v = ffbi_view_v(state, i, current) ## i64
        source_w = ffbi_view_w(state, i, current) ## i64
        transformed_u = ffbr_transform_factor(source_u, source_v, source_w, n, code, reverse, 0) ## i64
        transformed_v = ffbr_transform_factor(source_u, source_v, source_w, n, code, reverse, 1) ## i64
        transformed_w = ffbr_transform_factor(source_u, source_v, source_w, n, code, reverse, 2) ## i64
        h1 = ffbi_term_hash(transformed_u, transformed_v, transformed_w, 0) ## i64
        h2 = ffbi_term_hash(transformed_u, transformed_v, transformed_w, 1) ## i64
        sum1 = (sum1 + h1) % 2147483647
        square1 = (square1 + (h1 * h1) % 2147483647) % 2147483647
        sum2 = (sum2 + h2) % 2147483647
        square2 = (square2 + (h2 * h2) % 2147483647) % 2147483647
        bits += ffw_popcount(transformed_u) + ffw_popcount(transformed_v) + ffw_popcount(transformed_w)
        i += 1
      digest1 = (sum1 * 65537 + square1 + rank * 8191 + bits * 127 + gl) % 2147483647 ## i64
      digest2 = (sum2 * 1009 + square2 + rank * 131071 + bits * 31 + gl * 17) % 2147483647 ## i64
      candidate = (digest1 << 31) ^ digest2 ## i64
      if candidate < minimum
        minimum = candidate
      code += 1
    reverse += 1
  minimum

-> ffbr_active_basin_stats(states, best, stats)
  count = states.size() ## i64
  unique = 0 ## i64
  on_leader = 0 ## i64
  distance_sum = 0 ## i64
  min_distance = 0 - 1 ## i64
  if count > 1
    min_distance = 999999999
  # No temporary identities[] — campaign-lifetime allocator retained one
  # J-word array every TUI frame under the previous version.
  i = 0 ## i64
  while i < count
    id_i = ffbr_identity_view(states[i], 1) ## i64
    seen = 0 ## i64
    j = 0 ## i64
    while j < i
      id_j = ffbr_identity_view(states[j], 1) ## i64
      pair_distance = 0 ## i64
      if id_i != id_j
        pair_distance = ffn_current_distance_raw(states[i], states[j])
      if pair_distance < min_distance
        min_distance = pair_distance
      if pair_distance == 0
        seen = 1
      j += 1
    if seen == 0
      unique += 1
    distance = ffn_current_to_best_distance_known_ids(states[i], best, ffbr_identity_view(states[i], 1), ffbr_identity_view(best, 0)) ## i64
    if distance == 0
      on_leader += 1
    distance_sum += distance
    i += 1
  stats[0] = unique
  stats[1] = min_distance
  stats[2] = on_leader
  stats[3] = 0
  if count > 0
    stats[3] = distance_sum / count
  unique
