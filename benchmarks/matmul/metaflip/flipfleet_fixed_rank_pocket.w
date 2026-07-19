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
