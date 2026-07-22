use flipfleet_block_composer

# Fixed-rank flip-pocket closure.
#
# A pocket is the small symmetric difference between two exact schemes.  The
# terms outside the pocket are frozen; inside it, this operator exhaustively
# enumerates ordinary two-term flips to a bounded depth.  Unlike the main
# random walker, the search keeps every distinct fixed-rank presentation in
# the bound and may therefore cross a short density-uphill edge before it
# closes on the requested endpoint.
#
# Factors are represented as scalar i64 masks.  The loader/materializer below
# supports the one- and two-limb (at most 60-bit) FFBC representation, which
# covers every factor in the current <=7 matrix-multiplication campaigns.

-> fffrp_popcount(value) (i64) i64
  count = 0 ## i64
  x = value ## i64
  while x != 0
    x = x & (x - 1)
    count += 1
  count

-> fffrp_term_compare(au, av, aw, bu, bv, bw) (i64 i64 i64 i64 i64 i64) i64
  if au < bu
    return 0 - 1
  if au > bu
    return 1
  if av < bv
    return 0 - 1
  if av > bv
    return 1
  if aw < bw
    return 0 - 1
  if aw > bw
    return 1
  0

-> fffrp_sort_terms(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  i = 1 ## i64
  while i < count
    u = us[i] ## i64
    v = vs[i] ## i64
    w = ws[i] ## i64
    j = i ## i64
    while j > 0 && fffrp_term_compare(u, v, w, us[j - 1], vs[j - 1], ws[j - 1]) < 0
      us[j] = us[j - 1]
      vs[j] = vs[j - 1]
      ws[j] = ws[j - 1]
      j -= 1
    us[j] = u
    vs[j] = v
    ws[j] = w
    i += 1
  1

-> fffrp_terms_equal(au, av, aw, a_base, bu, bv, bw, b_base, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if au[a_base + i] != bu[b_base + i] || av[a_base + i] != bv[b_base + i] || aw[a_base + i] != bw[b_base + i]
      return 0
    i += 1
  1

-> fffrp_density(us, vs, ws, base, count) (i64[] i64[] i64[] i64 i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += fffrp_popcount(us[base + i])
    density += fffrp_popcount(vs[base + i])
    density += fffrp_popcount(ws[base + i])
    i += 1
  density

-> fffrp_copy_terms(src_u, src_v, src_w, src_base, dst_u, dst_v, dst_w, dst_base, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    dst_u[dst_base + i] = src_u[src_base + i]
    dst_v[dst_base + i] = src_v[src_base + i]
    dst_w[dst_base + i] = src_w[src_base + i]
    i += 1
  count

# Materialize one legal ordinary flip. Axis 0/1/2 means the pair shares
# U/V/W, respectively. Rank-changing cancellations are deliberately rejected:
# this operator explores one fixed-rank pocket only.
-> fffrp_flip_neighbor(src_u, src_v, src_w, src_base, count, left, right, axis, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if left < 0 || right <= left || right >= count || axis < 0 || axis > 2
    return 0
  ui = src_u[src_base + left] ## i64
  vi = src_v[src_base + left] ## i64
  wi = src_w[src_base + left] ## i64
  uj = src_u[src_base + right] ## i64
  vj = src_v[src_base + right] ## i64
  wj = src_w[src_base + right] ## i64
  if axis == 0 && ui != uj
    return 0
  if axis == 1 && vi != vj
    return 0
  if axis == 2 && wi != wj
    return 0

  au = ui ## i64
  av = vi ## i64
  aw = wi ## i64
  bu = ui ## i64
  bv = vi ## i64
  bw = wj ## i64
  if axis == 0
    aw = wi ^ wj
    bv = vi ^ vj
  if axis == 1
    aw = wi ^ wj
    bu = ui ^ uj
  if axis == 2
    av = vi ^ vj
    bu = ui ^ uj
    bv = vj
    bw = wi
  if au == 0 || av == 0 || aw == 0 || bu == 0 || bv == 0 || bw == 0
    return 0

  at = 0 ## i64
  i = 0 ## i64
  while i < count
    if i != left && i != right
      out_u[at] = src_u[src_base + i]
      out_v[at] = src_v[src_base + i]
      out_w[at] = src_w[src_base + i]
      at += 1
    i += 1
  out_u[at] = au
  out_v[at] = av
  out_w[at] = aw
  at += 1
  out_u[at] = bu
  out_v[at] = bv
  out_w[at] = bw
  at += 1
  fffrp_sort_terms(out_u, out_v, out_w, at)
  i = 1
  while i < at
    if out_u[i] == out_u[i - 1] && out_v[i] == out_v[i - 1] && out_w[i] == out_w[i - 1]
      return 0
    i += 1
  at

-> fffrp_seen(states_u, states_v, states_w, total, count, candidate_u, candidate_v, candidate_w) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  state = 0 ## i64
  while state < total
    if fffrp_terms_equal(states_u, states_v, states_w, state * count, candidate_u, candidate_v, candidate_w, 0, count) == 1
      return state
    state += 1
  0 - 1

# Deterministic bounded BFS. `max_uphill` is an edge-local density-debt
# allowance: 0 enforces monotone descent, 1 permits a one-bit uphill edge, and
# a negative value disables density pruning. The root is canonicalized, so
# term order never changes discovery.
#
# stats:
#   [0] states, [1] legal neighbors, [2] duplicates, [3] density prunes,
#   [4] found depth (-1 on miss), [5] source density, [6] target density,
#   [7] endpoint density, [8] largest uphill edge on the retained path,
#   [9] state-capacity exhaustion, [10] generated proposals.
-> fffrp_search(source_u, source_v, source_w, target_u, target_v, target_w, count, max_depth, max_states, max_uphill, endpoint_u, endpoint_v, endpoint_w, path_densities, path_axes, stats) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  if stats.size() > 4
    stats[4] = 0 - 1
  if count < 1 || max_depth < 0 || max_states < 1 || stats.size() < 11
    return 0
  if source_u.size() < count || source_v.size() < count || source_w.size() < count || target_u.size() < count || target_v.size() < count || target_w.size() < count
    return 0
  if endpoint_u.size() < count || endpoint_v.size() < count || endpoint_w.size() < count || path_densities.size() < max_depth + 1 || path_axes.size() < max_depth + 1
    return 0

  states_u = i64[max_states * count]
  states_v = i64[max_states * count]
  states_w = i64[max_states * count]
  parents = i64[max_states]
  depths = i64[max_states]
  densities = i64[max_states]
  axes = i64[max_states]
  root_u = i64[count]
  root_v = i64[count]
  root_w = i64[count]
  goal_u = i64[count]
  goal_v = i64[count]
  goal_w = i64[count]
  fffrp_copy_terms(source_u, source_v, source_w, 0, root_u, root_v, root_w, 0, count)
  fffrp_copy_terms(target_u, target_v, target_w, 0, goal_u, goal_v, goal_w, 0, count)
  fffrp_sort_terms(root_u, root_v, root_w, count)
  fffrp_sort_terms(goal_u, goal_v, goal_w, count)
  fffrp_copy_terms(root_u, root_v, root_w, 0, states_u, states_v, states_w, 0, count)
  parents[0] = 0 - 1
  axes[0] = 0 - 1
  densities[0] = fffrp_density(root_u, root_v, root_w, 0, count)
  stats[0] = 1
  stats[5] = densities[0]
  stats[6] = fffrp_density(goal_u, goal_v, goal_w, 0, count)
  total = 1 ## i64
  head = 0 ## i64
  found = 0 - 1 ## i64
  scratch_u = i64[count]
  scratch_v = i64[count]
  scratch_w = i64[count]

  while head < total && found < 0
    if fffrp_terms_equal(states_u, states_v, states_w, head * count, goal_u, goal_v, goal_w, 0, count) == 1
      found = head
    if found < 0 && depths[head] < max_depth
      left = 0 ## i64
      while left < count - 1 && found < 0
        right = left + 1 ## i64
        while right < count && found < 0
          axis = 0 ## i64
          while axis < 3 && found < 0
            stats[10] = stats[10] + 1
            made = fffrp_flip_neighbor(states_u, states_v, states_w, head * count, count, left, right, axis, scratch_u, scratch_v, scratch_w) ## i64
            if made == count
              stats[1] = stats[1] + 1
              candidate_density = fffrp_density(scratch_u, scratch_v, scratch_w, 0, count) ## i64
              allowed = 1 ## i64
              if max_uphill >= 0 && candidate_density > densities[head] + max_uphill
                allowed = 0
                stats[3] = stats[3] + 1
              if allowed == 1
                prior = fffrp_seen(states_u, states_v, states_w, total, count, scratch_u, scratch_v, scratch_w) ## i64
                if prior >= 0
                  stats[2] = stats[2] + 1
                if prior < 0
                  if total >= max_states
                    stats[9] = 1
                    return 0 - 1
                  fffrp_copy_terms(scratch_u, scratch_v, scratch_w, 0, states_u, states_v, states_w, total * count, count)
                  parents[total] = head
                  depths[total] = depths[head] + 1
                  densities[total] = candidate_density
                  axes[total] = axis
                  if fffrp_terms_equal(scratch_u, scratch_v, scratch_w, 0, goal_u, goal_v, goal_w, 0, count) == 1
                    found = total
                  total += 1
                  stats[0] = total
            axis += 1
          right += 1
        left += 1
    head += 1

  if found < 0
    return 0
  fffrp_copy_terms(states_u, states_v, states_w, found * count, endpoint_u, endpoint_v, endpoint_w, 0, count)
  depth = depths[found] ## i64
  stats[4] = depth
  stats[7] = densities[found]
  cursor = found ## i64
  while cursor >= 0
    position = depths[cursor] ## i64
    if position < path_densities.size()
      path_densities[position] = densities[cursor]
    if position > 0 && position < path_axes.size()
      path_axes[position] = axes[cursor]
    parent = parents[cursor] ## i64
    if parent >= 0
      rise = densities[cursor] - densities[parent] ## i64
      if rise > stats[8]
        stats[8] = rise
    cursor = parent
  depth

-> fffrp_scalar_factor(data, base, words) (i64[] i64 i64) i64
  if words < 1 || words > 2
    return 0 - 1
  value = data[base] ## i64
  if words == 2
    value += data[base + 1] << 30
  value

-> fffrp_scalar_term(scheme, term, output) (FFBCScheme i64 i64[]) i64
  if scheme == nil || output.size() < 3 || scheme.uw() > 2 || scheme.vw() > 2 || scheme.ww() > 2
    return 0
  output[0] = fffrp_scalar_factor(scheme.us(), term * scheme.uw(), scheme.uw())
  output[1] = fffrp_scalar_factor(scheme.vs(), term * scheme.vw(), scheme.vw())
  output[2] = fffrp_scalar_factor(scheme.ws(), term * scheme.ww(), scheme.ww())
  if output[0] <= 0 || output[1] <= 0 || output[2] <= 0
    return 0
  1

-> fffrp_scheme_has_scalar(scheme, u, v, w) (FFBCScheme i64 i64 i64) i64
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) == 1
      if term[0] == u && term[1] == v && term[2] == w
        return 1
    i += 1
  0

# Extract the symmetric-difference pocket shared by two equal-rank schemes.
# Returns the pocket size, or -1 if it exceeds capacity or the side sizes do
# not agree.
-> fffrp_extract_pocket(source, target, source_u, source_v, source_w, target_u, target_v, target_w) (FFBCScheme FFBCScheme i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if source == nil || target == nil || source.rank() != target.rank()
    return 0 - 1
  term = i64[3]
  source_count = 0 ## i64
  i = 0 ## i64
  while i < source.rank()
    if fffrp_scalar_term(source, i, term) != 1
      return 0 - 1
    if fffrp_scheme_has_scalar(target, term[0], term[1], term[2]) == 0
      if source_count >= source_u.size() || source_count >= source_v.size() || source_count >= source_w.size()
        return 0 - 1
      source_u[source_count] = term[0]
      source_v[source_count] = term[1]
      source_w[source_count] = term[2]
      source_count += 1
    i += 1
  target_count = 0 ## i64
  i = 0
  while i < target.rank()
    if fffrp_scalar_term(target, i, term) != 1
      return 0 - 1
    if fffrp_scheme_has_scalar(source, term[0], term[1], term[2]) == 0
      if target_count >= target_u.size() || target_count >= target_v.size() || target_count >= target_w.size()
        return 0 - 1
      target_u[target_count] = term[0]
      target_v[target_count] = term[1]
      target_w[target_count] = term[2]
      target_count += 1
    i += 1
  if source_count != target_count
    return 0 - 1
  fffrp_sort_terms(source_u, source_v, source_w, source_count)
  fffrp_sort_terms(target_u, target_v, target_w, target_count)
  source_count

-> fffrp_write_scalar(data, base, words, value) (i64[] i64 i64 i64) i64
  if words < 1 || words > 2 || value <= 0
    return 0
  x = value ## i64
  i = 0 ## i64
  while i < words
    data[base + i] = x & 1073741823
    x = x >> 30
    i += 1
  if x != 0
    return 0
  1

-> fffrp_write_term(scheme, slot, u, v, w) (FFBCScheme i64 i64 i64 i64) i64
  if fffrp_write_scalar(scheme.us(), slot * scheme.uw(), scheme.uw(), u) != 1
    return 0
  if fffrp_write_scalar(scheme.vs(), slot * scheme.vw(), scheme.vw(), v) != 1
    return 0
  if fffrp_write_scalar(scheme.ws(), slot * scheme.ww(), scheme.ww(), w) != 1
    return 0
  1

-> fffrp_pocket_has(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return 1
    i += 1
  0

# Replace the source pocket with an endpoint and independently gate the whole
# reconstructed matrix-multiplication tensor.
-> fffrp_materialize_endpoint(source, source_u, source_v, source_w, endpoint_u, endpoint_v, endpoint_w, pocket_count) (FFBCScheme i64[] i64[] i64[] i64[] i64[] i64[] i64)
  if source == nil || pocket_count < 1
    return nil
  if source_u.size() < pocket_count || source_v.size() < pocket_count || source_w.size() < pocket_count || endpoint_u.size() < pocket_count || endpoint_v.size() < pocket_count || endpoint_w.size() < pocket_count
    return nil
  result = FFBCScheme.new(source.n(), source.m(), source.p(), source.rank())
  term = i64[3]
  at = 0 ## i64
  i = 0 ## i64
  while i < source.rank()
    if fffrp_scalar_term(source, i, term) != 1
      return nil
    if fffrp_pocket_has(source_u, source_v, source_w, pocket_count, term[0], term[1], term[2]) == 0
      if at >= source.rank() || fffrp_write_term(result, at, term[0], term[1], term[2]) != 1
        return nil
      at += 1
    i += 1
  i = 0
  while i < pocket_count
    if at >= source.rank() || fffrp_write_term(result, at, endpoint_u[i], endpoint_v[i], endpoint_w[i]) != 1
      return nil
    at += 1
    i += 1
  if at != source.rank()
    return nil
  result.set_rank(at)
  if ffbc_verify_exact(result) != 1
    return nil
  result

# ---- Autonomous support-overlap pocket selection ------------------------
#
# The endpoint-directed search above is an oracle/control.  A fleet cannot
# know the other endpoint in advance.  The autonomous selector instead uses
# each currently legal equal-factor pair as a ticket.  After the first flip,
# a term from the frozen scheme may enter the pocket only when it shares the
# factor required by a legal next flip with a live pocket term.  Thus the
# pocket grows along the actual factor-overlap graph created by the word; no
# target scheme, archive difference, or pre-recorded recipe is consulted.
#
# A state stores (a) the sorted source indices whose terms have entered the
# pocket and (b) the sorted current local presentation.  These are separate:
# flips destroy the correspondence between a source term and an endpoint
# term.  Whole-scheme density debt is exactly
#
#   density(current local terms) - density(replaced source terms).
#
# so edge debt can be gated without materializing the other rank-k terms.

-> fffrp_origin_has(origins, base, count, value) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if origins[base + i] == value
      return 1
    i += 1
  0

-> fffrp_sort_origins(origins, count) (i64[] i64) i64
  i = 1 ## i64
  while i < count
    value = origins[i] ## i64
    j = i ## i64
    while j > 0 && origins[j - 1] > value
      origins[j] = origins[j - 1]
      j -= 1
    origins[j] = value
    i += 1
  1

-> fffrp_origin_density(source_u, source_v, source_w, origins, origin_base, count) (i64[] i64[] i64[] i64[] i64 i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    slot = origins[origin_base + i] ## i64
    density += fffrp_popcount(source_u[slot])
    density += fffrp_popcount(source_v[slot])
    density += fffrp_popcount(source_w[slot])
    i += 1
  density

-> fffrp_state_equal(state_u, state_v, state_w, state_origins, state_base, state_count, candidate_u, candidate_v, candidate_w, candidate_origins, count) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64) i64
  if state_count != count
    return 0
  if fffrp_terms_equal(state_u, state_v, state_w, state_base, candidate_u, candidate_v, candidate_w, 0, count) != 1
    return 0
  i = 0 ## i64
  while i < count
    if state_origins[state_base + i] != candidate_origins[i]
      return 0
    i += 1
  1

-> fffrp_seen_variable(states_u, states_v, states_w, states_origins, counts, total, stride, candidate_u, candidate_v, candidate_w, candidate_origins, count) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64) i64
  state = 0 ## i64
  while state < total
    if fffrp_state_equal(states_u, states_v, states_w, states_origins, state * stride, counts[state], candidate_u, candidate_v, candidate_w, candidate_origins, count) == 1
      return state
    state += 1
  0 - 1

-> fffrp_hash_mix(hash, value) (i64 i64) i64
  x = value ^ (value >> 21) ^ (value >> 42) ## i64
  ((hash ^ x) * 2654435761 + 40503) & 9223372036854775807

-> fffrp_variable_hash(us, vs, ws, term_base, origins, origin_base, count) (i64[] i64[] i64[] i64 i64[] i64 i64) i64
  hash = fffrp_hash_mix(1469598103934665603, count) ## i64
  i = 0 ## i64
  while i < count
    hash = fffrp_hash_mix(hash, origins[origin_base + i] + 1)
    hash = fffrp_hash_mix(hash, us[term_base + i])
    hash = fffrp_hash_mix(hash, vs[term_base + i])
    hash = fffrp_hash_mix(hash, ws[term_base + i])
    i += 1
  hash

-> fffrp_seen_variable_hashed(states_u, states_v, states_w, states_origins, counts, stride, candidate_u, candidate_v, candidate_w, candidate_origins, count, candidate_hash, hash_heads, hash_next, hash_mask) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  cursor = hash_heads[candidate_hash & hash_mask] ## i64
  while cursor != 0
    state = cursor - 1 ## i64
    if fffrp_state_equal(states_u, states_v, states_w, states_origins, state * stride, counts[state], candidate_u, candidate_v, candidate_w, candidate_origins, count) == 1
      return state
    cursor = hash_next[state]
  0 - 1

-> fffrp_hash_link(hash_heads, hash_next, hash_mask, state, hash) (i64[] i64[] i64 i64 i64) i64
  bucket = hash & hash_mask ## i64
  hash_next[state] = hash_heads[bucket]
  hash_heads[bucket] = state + 1
  1

-> fffrp_frozen_collision(source_u, source_v, source_w, source_count, origins, origin_count, candidate_u, candidate_v, candidate_w, count) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    slot = 0 ## i64
    while slot < source_count
      if fffrp_origin_has(origins, 0, origin_count, slot) == 0
        if candidate_u[i] == source_u[slot] && candidate_v[i] == source_v[slot] && candidate_w[i] == source_w[slot]
          return 1
      slot += 1
    i += 1
  0

# Deterministic ticket enumeration.  A pair sharing two axes contributes two
# tickets because the two ordinary flips are algebraically distinct.
-> fffrp_ticket(source_u, source_v, source_w, source_count, wanted, ticket_out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if ticket_out.size() < 3
    return 0
  seen = 0 ## i64
  left = 0 ## i64
  while left < source_count - 1
    right = left + 1 ## i64
    while right < source_count
      axis = 0 ## i64
      while axis < 3
        equal = 0 ## i64
        if axis == 0 && source_u[left] == source_u[right]
          equal = 1
        if axis == 1 && source_v[left] == source_v[right]
          equal = 1
        if axis == 2 && source_w[left] == source_w[right]
          equal = 1
        if equal == 1
          if seen == wanted
            ticket_out[0] = left
            ticket_out[1] = right
            ticket_out[2] = axis
            return 1
          seen += 1
        axis += 1
      right += 1
    left += 1
  0

-> fffrp_ticket_count(source_u, source_v, source_w, source_count) (i64[] i64[] i64[] i64) i64
  total = 0 ## i64
  left = 0 ## i64
  while left < source_count - 1
    right = left + 1 ## i64
    while right < source_count
      if source_u[left] == source_u[right]
        total += 1
      if source_v[left] == source_v[right]
        total += 1
      if source_w[left] == source_w[right]
        total += 1
      right += 1
    left += 1
  total

-> fffrp_copy_variable_state(states_u, states_v, states_w, states_origins, source_state, target_state, stride, count) (i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  source_base = source_state * stride ## i64
  target_base = target_state * stride ## i64
  i = 0 ## i64
  while i < count
    states_u[target_base + i] = states_u[source_base + i]
    states_v[target_base + i] = states_v[source_base + i]
    states_w[target_base + i] = states_w[source_base + i]
    states_origins[target_base + i] = states_origins[source_base + i]
    i += 1
  count

# Explore one autonomous ticket.  The root contains the ticket's two source
# terms; subsequent legal flips may recruit at most `max_terms - 2` frozen
# source terms.  `max_edge_uphill < 0` disables the ordinary walker's local
# density gate.  The best net density endpoint is returned, even when its
# shortest retained path temporarily exceeds that gate.
#
# stats:
#   [0] states, [1] proposals, [2] legal, [3] duplicates,
#   [4] frozen collisions, [5] best gain, [6] best depth,
#   [7] best pocket terms, [8] largest uphill edge on best path,
#   [9] capacity exhaustion, [10] density-gate prunes,
#   [11] endpoint density, [12] replaced-source density.
-> fffrp_autonomous_ticket(source_u, source_v, source_w, source_count, ticket, max_terms, max_depth, max_states, max_edge_uphill, endpoint_u, endpoint_v, endpoint_w, endpoint_origins, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < stats.size()
    stats[i] = 0
    i += 1
  if source_count < 2 || max_terms < 2 || max_depth < 1 || max_states < 1 || stats.size() < 13
    return 0
  if endpoint_u.size() < max_terms || endpoint_v.size() < max_terms || endpoint_w.size() < max_terms || endpoint_origins.size() < max_terms
    return 0
  ticket_info = i64[3]
  if fffrp_ticket(source_u, source_v, source_w, source_count, ticket, ticket_info) != 1
    return 0

  stride = max_terms ## i64
  states_u = i64[max_states * stride]
  states_v = i64[max_states * stride]
  states_w = i64[max_states * stride]
  states_origins = i64[max_states * stride]
  counts = i64[max_states]
  depths = i64[max_states]
  parents = i64[max_states]
  move_axes = i64[max_states]
  densities = i64[max_states]
  source_densities = i64[max_states]
  max_rises = i64[max_states]
  hash_capacity = 16 ## i64
  while hash_capacity < max_states * 2
    hash_capacity = hash_capacity * 2
  hash_heads = i64[hash_capacity]
  hash_next = i64[max_states]
  hash_mask = hash_capacity - 1 ## i64

  left = ticket_info[0] ## i64
  right = ticket_info[1] ## i64
  states_u[0] = source_u[left]
  states_v[0] = source_v[left]
  states_w[0] = source_w[left]
  states_u[1] = source_u[right]
  states_v[1] = source_v[right]
  states_w[1] = source_w[right]
  fffrp_sort_terms(states_u, states_v, states_w, 2)
  states_origins[0] = left
  states_origins[1] = right
  fffrp_sort_origins(states_origins, 2)
  counts[0] = 2
  parents[0] = 0 - 1
  move_axes[0] = 0 - 1
  densities[0] = fffrp_density(states_u, states_v, states_w, 0, 2)
  source_densities[0] = densities[0]
  stats[0] = 1
  root_hash = fffrp_variable_hash(states_u, states_v, states_w, 0, states_origins, 0, 2) ## i64
  fffrp_hash_link(hash_heads, hash_next, hash_mask, 0, root_hash)
  total = 1 ## i64
  head = 0 ## i64
  best = 0 ## i64

  scratch_u = i64[max_terms]
  scratch_v = i64[max_terms]
  scratch_w = i64[max_terms]
  scratch_origins = i64[max_terms]
  input_u = i64[max_terms]
  input_v = i64[max_terms]
  input_w = i64[max_terms]

  while head < total
    count = counts[head] ## i64
    base = head * stride ## i64
    if depths[head] < max_depth
      # Moves internal to the currently selected pocket.
      pair_left = 0 ## i64
      while pair_left < count - 1
        pair_right = pair_left + 1 ## i64
        while pair_right < count
          axis = 0 ## i64
          while axis < 3
            stats[1] = stats[1] + 1
            made = fffrp_flip_neighbor(states_u, states_v, states_w, base, count, pair_left, pair_right, axis, scratch_u, scratch_v, scratch_w) ## i64
            if made == count
              stats[2] = stats[2] + 1
              i = 0
              while i < count
                scratch_origins[i] = states_origins[base + i]
                i += 1
              candidate_density = fffrp_density(scratch_u, scratch_v, scratch_w, 0, count) ## i64
              rise = candidate_density - densities[head] ## i64
              allowed = 1 ## i64
              if max_edge_uphill >= 0 && rise > max_edge_uphill
                allowed = 0
                stats[10] = stats[10] + 1
              if allowed == 1 && fffrp_frozen_collision(source_u, source_v, source_w, source_count, scratch_origins, count, scratch_u, scratch_v, scratch_w, count) == 1
                allowed = 0
                stats[4] = stats[4] + 1
              if allowed == 1
                candidate_hash = fffrp_variable_hash(scratch_u, scratch_v, scratch_w, 0, scratch_origins, 0, count) ## i64
                prior = fffrp_seen_variable_hashed(states_u, states_v, states_w, states_origins, counts, stride, scratch_u, scratch_v, scratch_w, scratch_origins, count, candidate_hash, hash_heads, hash_next, hash_mask) ## i64
                if prior >= 0
                  stats[3] = stats[3] + 1
                if prior < 0
                  if total >= max_states
                    stats[9] = 1
                  if total < max_states
                    target_base = total * stride ## i64
                    fffrp_copy_terms(scratch_u, scratch_v, scratch_w, 0, states_u, states_v, states_w, target_base, count)
                    i = 0
                    while i < count
                      states_origins[target_base + i] = scratch_origins[i]
                      i += 1
                    counts[total] = count
                    depths[total] = depths[head] + 1
                    parents[total] = head
                    move_axes[total] = axis
                    densities[total] = candidate_density
                    source_densities[total] = source_densities[head]
                    max_rises[total] = max_rises[head]
                    if rise > max_rises[total]
                      max_rises[total] = rise
                    gain = source_densities[total] - candidate_density ## i64
                    best_gain = source_densities[best] - densities[best] ## i64
                    if gain > best_gain
                      best = total
                    fffrp_hash_link(hash_heads, hash_next, hash_mask, total, candidate_hash)
                    total += 1
                    stats[0] = total
              axis += 1
            else
              axis += 1
          pair_right += 1
        pair_left += 1

      # Grow the support-overlap pocket by one source term, but only through
      # a legal factor-sharing flip with a current local term.
      if count < max_terms
        local = 0 ## i64
        while local < count
          source_slot = 0 ## i64
          while source_slot < source_count
            if fffrp_origin_has(states_origins, base, count, source_slot) == 0
              fffrp_copy_terms(states_u, states_v, states_w, base, input_u, input_v, input_w, 0, count)
              input_u[count] = source_u[source_slot]
              input_v[count] = source_v[source_slot]
              input_w[count] = source_w[source_slot]
              i = 0
              while i < count
                scratch_origins[i] = states_origins[base + i]
                i += 1
              scratch_origins[count] = source_slot
              fffrp_sort_origins(scratch_origins, count + 1)
              axis = 0
              while axis < 3
                stats[1] = stats[1] + 1
                made = fffrp_flip_neighbor(input_u, input_v, input_w, 0, count + 1, local, count, axis, scratch_u, scratch_v, scratch_w) ## i64
                if made == count + 1
                  stats[2] = stats[2] + 1
                  candidate_density = fffrp_density(scratch_u, scratch_v, scratch_w, 0, count + 1) ## i64
                  candidate_source_density = source_densities[head] ## i64
                  candidate_source_density += fffrp_popcount(source_u[source_slot]) + fffrp_popcount(source_v[source_slot]) + fffrp_popcount(source_w[source_slot])
                  parent_delta = densities[head] - source_densities[head] ## i64
                  candidate_delta = candidate_density - candidate_source_density ## i64
                  rise = candidate_delta - parent_delta ## i64
                  allowed = 1 ## i64
                  if max_edge_uphill >= 0 && rise > max_edge_uphill
                    allowed = 0
                    stats[10] = stats[10] + 1
                  if allowed == 1 && fffrp_frozen_collision(source_u, source_v, source_w, source_count, scratch_origins, count + 1, scratch_u, scratch_v, scratch_w, count + 1) == 1
                    allowed = 0
                    stats[4] = stats[4] + 1
                  if allowed == 1
                    candidate_hash = fffrp_variable_hash(scratch_u, scratch_v, scratch_w, 0, scratch_origins, 0, count + 1) ## i64
                    prior = fffrp_seen_variable_hashed(states_u, states_v, states_w, states_origins, counts, stride, scratch_u, scratch_v, scratch_w, scratch_origins, count + 1, candidate_hash, hash_heads, hash_next, hash_mask) ## i64
                    if prior >= 0
                      stats[3] = stats[3] + 1
                    if prior < 0
                      if total >= max_states
                        stats[9] = 1
                      if total < max_states
                        target_base = total * stride ## i64
                        fffrp_copy_terms(scratch_u, scratch_v, scratch_w, 0, states_u, states_v, states_w, target_base, count + 1)
                        i = 0
                        while i < count + 1
                          states_origins[target_base + i] = scratch_origins[i]
                          i += 1
                        counts[total] = count + 1
                        depths[total] = depths[head] + 1
                        parents[total] = head
                        move_axes[total] = axis
                        densities[total] = candidate_density
                        source_densities[total] = candidate_source_density
                        max_rises[total] = max_rises[head]
                        if rise > max_rises[total]
                          max_rises[total] = rise
                        gain = candidate_source_density - candidate_density ## i64
                        best_gain = source_densities[best] - densities[best] ## i64
                        if gain > best_gain
                          best = total
                        fffrp_hash_link(hash_heads, hash_next, hash_mask, total, candidate_hash)
                        total += 1
                        stats[0] = total
                axis += 1
            source_slot += 1
          local += 1
    head += 1

  best_count = counts[best] ## i64
  best_base = best * stride ## i64
  fffrp_copy_terms(states_u, states_v, states_w, best_base, endpoint_u, endpoint_v, endpoint_w, 0, best_count)
  i = 0
  while i < best_count
    endpoint_origins[i] = states_origins[best_base + i]
    i += 1
  stats[5] = source_densities[best] - densities[best]
  stats[6] = depths[best]
  stats[7] = best_count
  stats[8] = max_rises[best]
  stats[11] = densities[best]
  stats[12] = source_densities[best]
  # Optional compact replay trace for tests, certificates, and move intake:
  # [13] depth, [14..19] whole-scheme density deltas by depth,
  # [20..25] flip axes (root=-1), [26..31] pocket term counts.
  if stats.size() >= 32
    stats[13] = depths[best]
    cursor = best ## i64
    while cursor >= 0
      position = depths[cursor] ## i64
      if position <= 5
        stats[14 + position] = densities[cursor] - source_densities[cursor]
        stats[20 + position] = move_axes[cursor]
        stats[26 + position] = counts[cursor]
      cursor = parents[cursor]
  stats[5]

-> fffrp_scalar_scheme(scheme, source_u, source_v, source_w) (FFBCScheme i64[] i64[] i64[]) i64
  if scheme == nil || source_u.size() < scheme.rank() || source_v.size() < scheme.rank() || source_w.size() < scheme.rank()
    return 0
  term = i64[3]
  i = 0 ## i64
  while i < scheme.rank()
    if fffrp_scalar_term(scheme, i, term) != 1
      return 0
    source_u[i] = term[0]
    source_v[i] = term[1]
    source_w[i] = term[2]
    i += 1
  scheme.rank()

-> fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, count) (FFBCScheme i64[] i64[] i64[] i64[] i64)
  if source == nil || count < 1 || origins.size() < count || endpoint_u.size() < count || endpoint_v.size() < count || endpoint_w.size() < count
    return nil
  result = FFBCScheme.new(source.n(), source.m(), source.p(), source.rank())
  term = i64[3]
  at = 0 ## i64
  i = 0 ## i64
  while i < source.rank()
    if fffrp_origin_has(origins, 0, count, i) == 0
      if fffrp_scalar_term(source, i, term) != 1 || fffrp_write_term(result, at, term[0], term[1], term[2]) != 1
        return nil
      at += 1
    i += 1
  i = 0
  while i < count
    if fffrp_write_term(result, at, endpoint_u[i], endpoint_v[i], endpoint_w[i]) != 1
      return nil
    at += 1
    i += 1
  if at != source.rank()
    return nil
  result.set_rank(at)
  if ffbc_verify_exact(result) != 1
    return nil
  result
