# Exact split-braid-merge holonomy for bounded local windows.
#
# This is the Rubik-style setup/trigger/unsetup move for Metaflip.  A selected
# term is split into two *labelled* summands, a connected braid of ordinary
# exact pair flips is applied at rank R+1, and a (possibly different) pair is
# XOR-merged back to rank R.  Intermediate shoulders never enter the normal
# objective gate.  Only a changed endpoint that passes an exact local tensor
# comparison is returned, together with a deterministic replay recipe.
#
# The search is intentionally coordinator-independent and bounded:
#   * 2..6 source terms;
#   * braid depth 1..4;
#   * a caller-supplied legal-edge cap;
#   * every braid edge must touch the connected active component begun by the
#     two split labels.
#
# Recipe layout (minimum 13 words):
#   [0] split source, [1] split axis, [2] split part, [3] braid depth
#   [4..7] ordered pair-flip codes, [8] merge first, [9] merge second,
#   [10] merge axis, [11] result rank, [12] endpoint distance.
#
# Search stats (minimum 12 words):
#   [0] codes examined, [1] legal braid edges, [2] merge closures,
#   [3] changed algebraic endpoints, [4] exact best updates,
#   [5] best rank (zero on miss), [6] best distance,
#   [7] best density delta, [8] best depth, [9] best pair-pressure delta,
#   [10] final replay exact, [11] legal-edge cap reached.
#
# Endpoint selection modes:
#   0 legacy: rank, distance, density, pair pressure
#   1 density goal: rank, density, pair pressure, distance; same-rank closes
#     must actually lower density.
#   2 pressure goal: rank, pair pressure, density, distance; same-rank closes
#     must actually increase pair pressure.

use tunnel

-> ffmh_axis_get(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  value = us[term] ## i64
  if axis == 1
    value = vs[term]
  if axis == 2
    value = ws[term]
  value

-> ffmh_axis_set(us, vs, ws, term, axis, value) (i64[] i64[] i64[] i64 i64 i64) i64
  if axis == 0
    us[term] = value
  if axis == 1
    vs[term] = value
  if axis == 2
    ws[term] = value
  value

-> ffmh_copy(source_u, source_v, source_w, count, dest_u, dest_v, dest_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    dest_u[i] = source_u[i]
    dest_v[i] = source_v[i]
    dest_w[i] = source_w[i]
    i += 1
  count

-> ffmh_copy_slot(source_u, source_v, source_w, source_offset, count, dest_u, dest_v, dest_w, dest_offset) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest_u[dest_offset+i] = source_u[source_offset+i]
    dest_v[dest_offset+i] = source_v[source_offset+i]
    dest_w[dest_offset+i] = source_w[source_offset+i]
    i += 1
  count

-> ffmh_split_labeled(us, vs, ws, count, capacity, source, axis, part) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if count < 1 || count >= capacity || source < 0 || source >= count || axis < 0 || axis > 2 || part <= 0
    return 0
  factor = ffmh_axis_get(us,vs,ws,source,axis) ## i64
  if factor == 0 || part == factor
    return 0
  other = factor ^ part ## i64
  if other == 0
    return 0
  us[count] = us[source]
  vs[count] = vs[source]
  ws[count] = ws[source]
  z = ffmh_axis_set(us,vs,ws,source,axis,part) ## i64
  z = ffmh_axis_set(us,vs,ws,count,axis,other)
  count + 1

# Return the lowest axis along which the pair can be merged.  Equality on the
# other two axes is the complete condition.  Duplicate labels therefore
# return axis zero and annihilate when merged.
-> ffmh_merge_axis(us, vs, ws, first, second) (i64[] i64[] i64[] i64 i64) i64
  if first < 0 || second < 0 || first >= us.size() || second >= us.size() || first == second
    return 0 - 1
  if vs[first] == vs[second] && ws[first] == ws[second]
    return 0
  if us[first] == us[second] && ws[first] == ws[second]
    return 1
  if us[first] == us[second] && vs[first] == vs[second]
    return 2
  0 - 1

# Merge two labelled terms.  A zero XOR is duplicate-pair annihilation and
# removes both labels.  Otherwise `first` receives the merged term and
# `second` is removed; no later braid edge observes the resulting relabel.
-> ffmh_merge_labeled(us, vs, ws, count, first, second, axis) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if count < 2 || first < 0 || second < 0 || first >= count || second >= count || first == second || axis < 0 || axis > 2
    return 0
  valid = 0 ## i64
  if axis == 0 && vs[first] == vs[second] && ws[first] == ws[second]
    valid = 1
  if axis == 1 && us[first] == us[second] && ws[first] == ws[second]
    valid = 1
  if axis == 2 && us[first] == us[second] && vs[first] == vs[second]
    valid = 1
  if valid == 0
    return 0
  merged = ffmh_axis_get(us,vs,ws,first,axis) ^ ffmh_axis_get(us,vs,ws,second,axis) ## i64
  high = second ## i64
  low = first ## i64
  if low > high
    swap = low ## i64
    low = high
    high = swap
  if merged == 0
    # Remove the high label first, then the low label.
    last = count - 1 ## i64
    us[high] = us[last]
    vs[high] = vs[last]
    ws[high] = ws[last]
    count -= 1
    last = count - 1
    us[low] = us[last]
    vs[low] = vs[last]
    ws[low] = ws[last]
    return count - 1
  z = ffmh_axis_set(us,vs,ws,first,axis,merged) ## i64
  last = count - 1 ## i64
  us[second] = us[last]
  vs[second] = vs[last]
  ws[second] = ws[last]
  count - 1

# Parity-compact a labelled list into an ordinary GF(2) term set.
-> ffmh_compact(us, vs, ws, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  out_count = 0 ## i64
  i = 0 ## i64
  while i < count
    if us[i] == 0 || vs[i] == 0 || ws[i] == 0
      return 0 - 1
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < out_count && found < 0
      if fftc_same_term(us[i],vs[i],ws[i],out_u[j],out_v[j],out_w[j]) == 1
        found = j
      j += 1
    if found >= 0
      last = out_count - 1 ## i64
      out_u[found] = out_u[last]
      out_v[found] = out_v[last]
      out_w[found] = out_w[last]
      out_count -= 1
    else
      if out_count >= out_u.size() || out_count >= out_v.size() || out_count >= out_w.size()
        return 0 - 1
      out_u[out_count] = us[i]
      out_v[out_count] = vs[i]
      out_w[out_count] = ws[i]
      out_count += 1
    i += 1
  out_count

-> ffmh_distance(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used = i64[right_count]
  common = 0 ## i64
  i = 0 ## i64
  while i < left_count
    found = 0 ## i64
    j = 0 ## i64
    while j < right_count && found == 0
      if used[j] == 0 && fftc_same_term(left_u[i],left_v[i],left_w[i],right_u[j],right_v[j],right_w[j]) == 1
        used[j] = 1
        common += 1
        found = 1
      j += 1
    i += 1
  left_count + right_count - common - common

-> ffmh_pair_pressure(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  pressure = 0 ## i64
  i = 0 ## i64
  while i < count
    j = i + 1 ## i64
    while j < count
      if us[i] == us[j]
        pressure += 1
      if vs[i] == vs[j]
        pressure += 1
      if ws[i] == ws[j]
        pressure += 1
      j += 1
    i += 1
  pressure

# Keep the macro-specific name as a stable replay/audit surface; the shared
# tunnel gate now uses the same packed support-parity reconstruction.
-> ffmh_local_exact(source_u, source_v, source_w, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  fftc_local_exact(source_u,source_v,source_w,source_count,out_u,out_v,out_w,out_count)

-> ffmh_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffmh_decode_code(code, count, pair) (i64 i64 i64[]) i64
  if code < 0 || count < 2 || pair.size() < 3
    return 0
  pair_code = code / 3 ## i64
  pair[2] = code % 3
  pair[0] = pair_code / (count - 1)
  offset = pair_code % (count - 1) ## i64
  pair[1] = offset
  if pair[1] >= pair[0]
    pair[1] += 1
  if pair[0] < 0 || pair[0] >= count || pair[1] < 0 || pair[1] >= count || pair[0] == pair[1]
    return 0
  1

-> ffmh_candidate_better(rank, distance, density, pressure, stats) (i64 i64 i64 i64 i64[]) i64
  ffmh_candidate_better_mode(rank,distance,density,pressure,0,stats)

-> ffmh_candidate_better_mode(rank, distance, density, pressure, mode, stats) (i64 i64 i64 i64 i64 i64[]) i64
  if stats[5] == 0 || rank < stats[5]
    return 1
  if rank > stats[5]
    return 0
  current_density = stats[7] ## i64
  current_pressure = stats[9] ## i64
  if mode == 1
    if density < current_density
      return 1
    if density > current_density
      return 0
    if pressure > current_pressure
      return 1
    if pressure < current_pressure
      return 0
    if distance > stats[6]
      return 1
    return 0
  if mode == 2
    if pressure > current_pressure
      return 1
    if pressure < current_pressure
      return 0
    if density < current_density
      return 1
    if density > current_density
      return 0
    if distance > stats[6]
      return 1
    return 0
  if distance > stats[6]
    return 1
  if distance < stats[6]
    return 0
  if density < current_density
    return 1
  if density > current_density
    return 0
  if pressure > current_pressure
    return 1
  0

-> ffmh_goal_satisfied(rank, source_rank, density, pressure, mode) (i64 i64 i64 i64 i64) i64
  if rank < source_rank
    return 1
  if rank > source_rank
    return 0
  if mode == 1
    if density < 0
      return 1
    return 0
  if mode == 2
    if pressure > 0
      return 1
    return 0
  1

# Depth-first connected braid enumeration over fixed caller-owned slabs.
-> ffmh_dfs(source_u, source_v, source_w, source_count, states_u, states_v, states_w, active, shoulder_count, depth, max_depth, max_edges, selection_mode, path, scratch_u, scratch_v, scratch_w, compact_u, compact_v, compact_w, best_u, best_v, best_w, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  offset = depth * shoulder_count ## i64
  active_offset = depth * shoulder_count ## i64
  if depth > 0
    # Evaluate every directed close available at this braid node.  Exact local
    # reconstruction runs only when a candidate improves the retained winner.
    source_density = fftc_density(source_u,source_v,source_w,source_count) ## i64
    source_pressure = ffmh_pair_pressure(source_u,source_v,source_w,source_count) ## i64
    first = 0 ## i64
    while first < shoulder_count
      second = first + 1 ## i64
      while second < shoulder_count
        if active[active_offset+first] != 0 || active[active_offset+second] != 0
          axis = ffmh_merge_axis(states_u,states_v,states_w,offset+first,offset+second) ## i64
          direct_close = 0 ## i64
          if axis == recipe[1]
            if first == recipe[0] && second == source_count
              direct_close = 1
            if second == recipe[0] && first == source_count
              direct_close = 1
          if axis >= 0 && direct_close == 0
            z = ffmh_copy_slot(states_u,states_v,states_w,offset,shoulder_count,scratch_u,scratch_v,scratch_w,0) ## i64
            merged = ffmh_merge_labeled(scratch_u,scratch_v,scratch_w,shoulder_count,first,second,axis) ## i64
            if merged > 0
              compacted = ffmh_compact(scratch_u,scratch_v,scratch_w,merged,compact_u,compact_v,compact_w) ## i64
              if compacted > 0
                stats[2] = stats[2] + 1
                distance = ffmh_distance(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) ## i64
                if distance > 0
                  stats[3] = stats[3] + 1
                  density = fftc_density(compact_u,compact_v,compact_w,compacted) ## i64
                  pressure = ffmh_pair_pressure(compact_u,compact_v,compact_w,compacted) ## i64
                  density_delta = density - source_density ## i64
                  pressure_delta = pressure - source_pressure ## i64
                  if ffmh_goal_satisfied(compacted,source_count,density_delta,pressure_delta,selection_mode) == 1 && ffmh_candidate_better_mode(compacted,distance,density_delta,pressure_delta,selection_mode,stats) == 1
                    if ffmh_local_exact(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) == 1
                      z = ffmh_copy(compact_u,compact_v,compact_w,compacted,best_u,best_v,best_w)
                      recipe[3] = depth
                      pi = 0 ## i64
                      while pi < 4
                        recipe[4+pi] = 0 - 1
                        if pi < depth
                          recipe[4+pi] = path[pi]
                        pi += 1
                      recipe[8] = first
                      recipe[9] = second
                      recipe[10] = axis
                      recipe[11] = compacted
                      recipe[12] = distance
                      stats[4] = stats[4] + 1
                      stats[5] = compacted
                      stats[6] = distance
                      stats[7] = density_delta
                      stats[8] = depth
                      stats[9] = pressure_delta
        second += 1
      first += 1
  if depth >= max_depth || stats[1] >= max_edges
    if stats[1] >= max_edges
      stats[11] = 1
    return stats[5]
  code_count = fftc_code_count(shoulder_count) ## i64
  code = 0 ## i64
  pair = i64[3]
  while code < code_count && stats[1] < max_edges
    stats[0] = stats[0] + 1
    if ffmh_decode_code(code,shoulder_count,pair) == 1
      connected = 0 ## i64
      if active[active_offset+pair[0]] != 0 || active[active_offset+pair[1]] != 0
        connected = 1
      # Every pair flip is an involution on its labelled ordered pair.
      if depth > 0 && path[depth-1] == code
        connected = 0
      if connected == 1
        child_offset = (depth+1) * shoulder_count ## i64
        # Apply against a compact scratch view because fftc_apply_code uses
        # zero-based labels, then copy the result into the child depth slab.
        z = ffmh_copy_slot(states_u,states_v,states_w,offset,shoulder_count,scratch_u,scratch_v,scratch_w,0)
        legal = fftc_apply_code(scratch_u,scratch_v,scratch_w,shoulder_count,code,0-1) ## i64
        if legal == 1
          z = ffmh_copy_slot(scratch_u,scratch_v,scratch_w,0,shoulder_count,states_u,states_v,states_w,child_offset)
          ai = 0 ## i64
          while ai < shoulder_count
            active[(depth+1)*shoulder_count+ai] = active[active_offset+ai]
            ai += 1
          active[(depth+1)*shoulder_count+pair[0]] = 1
          active[(depth+1)*shoulder_count+pair[1]] = 1
          path[depth] = code
          stats[1] = stats[1] + 1
          z = ffmh_dfs(source_u,source_v,source_w,source_count,states_u,states_v,states_w,active,shoulder_count,depth+1,max_depth,max_edges,selection_mode,path,scratch_u,scratch_v,scratch_w,compact_u,compact_v,compact_w,best_u,best_v,best_w,recipe,stats)
    code += 1
  if stats[1] >= max_edges
    stats[11] = 1
  stats[5]

# Deterministically replay and independently exact-gate a retained recipe.
# replay_meta: exact, changed, distance, density delta, pressure delta.
-> ffmh_replay(source_u, source_v, source_w, source_count, recipe, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 6 || recipe.size() < 13 || replay_meta.size() < 5
    return 0
  if out_u.size() < source_count+1 || out_v.size() < source_count+1 || out_w.size() < source_count+1
    return 0
  z = ffmh_clear(replay_meta,5) ## i64
  capacity = source_count + 1 ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffmh_copy(source_u,source_v,source_w,source_count,us,vs,ws)
  count = ffmh_split_labeled(us,vs,ws,source_count,capacity,recipe[0],recipe[1],recipe[2]) ## i64
  if count != capacity
    return 0
  depth = recipe[3] ## i64
  if depth < 1 || depth > 4
    return 0
  step = 0 ## i64
  while step < depth
    if fftc_apply_code(us,vs,ws,count,recipe[4+step],0-1) != 1
      return 0
    step += 1
  merged = ffmh_merge_labeled(us,vs,ws,count,recipe[8],recipe[9],recipe[10]) ## i64
  if merged < 1
    return 0
  compacted = ffmh_compact(us,vs,ws,merged,out_u,out_v,out_w) ## i64
  if compacted < 1 || compacted != recipe[11]
    return 0
  exact = ffmh_local_exact(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted) ## i64
  distance = ffmh_distance(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted) ## i64
  replay_meta[0] = exact
  if distance > 0
    replay_meta[1] = 1
  replay_meta[2] = distance
  replay_meta[3] = fftc_density(out_u,out_v,out_w,compacted) - fftc_density(source_u,source_v,source_w,source_count)
  replay_meta[4] = ffmh_pair_pressure(out_u,out_v,out_w,compacted) - ffmh_pair_pressure(source_u,source_v,source_w,source_count)
  if exact != 1 || distance < 1
    return 0
  compacted

# Search one explicit setup.  Part selection and local-window construction are
# deliberately left to the experiment/coordinator so rectangular factor
# widths and campaign-specific door policies remain outside this pure move.
-> ffmh_search(source_u, source_v, source_w, source_count, split_source, split_axis, part, max_depth, max_edges, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  ffmh_search_mode(source_u,source_v,source_w,source_count,split_source,split_axis,part,max_depth,max_edges,0,out_u,out_v,out_w,recipe,stats)

-> ffmh_search_mode(source_u, source_v, source_w, source_count, split_source, split_axis, part, max_depth, max_edges, selection_mode, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 6 || split_source < 0 || split_source >= source_count || split_axis < 0 || split_axis > 2 || part <= 0 || max_depth < 1 || max_depth > 4 || max_edges < 1 || selection_mode < 0 || selection_mode > 2
    return 0
  if out_u.size() < source_count+1 || out_v.size() < source_count+1 || out_w.size() < source_count+1 || recipe.size() < 13 || stats.size() < 12
    return 0
  z = ffmh_clear(stats,12) ## i64
  z = ffmh_clear(recipe,13)
  recipe[0] = split_source
  recipe[1] = split_axis
  recipe[2] = part
  shoulder_count = source_count + 1 ## i64
  states_u = i64[(max_depth+1)*shoulder_count]
  states_v = i64[(max_depth+1)*shoulder_count]
  states_w = i64[(max_depth+1)*shoulder_count]
  active = i64[(max_depth+1)*shoulder_count]
  z = ffmh_copy(source_u,source_v,source_w,source_count,states_u,states_v,states_w)
  if ffmh_split_labeled(states_u,states_v,states_w,source_count,shoulder_count,split_source,split_axis,part) != shoulder_count
    return 0
  active[split_source] = 1
  active[source_count] = 1
  path = i64[4]
  scratch_u = i64[shoulder_count]
  scratch_v = i64[shoulder_count]
  scratch_w = i64[shoulder_count]
  compact_u = i64[shoulder_count]
  compact_v = i64[shoulder_count]
  compact_w = i64[shoulder_count]
  best_u = i64[shoulder_count]
  best_v = i64[shoulder_count]
  best_w = i64[shoulder_count]
  z = ffmh_dfs(source_u,source_v,source_w,source_count,states_u,states_v,states_w,active,shoulder_count,0,max_depth,max_edges,selection_mode,path,scratch_u,scratch_v,scratch_w,compact_u,compact_v,compact_w,best_u,best_v,best_w,recipe,stats)
  if stats[5] < 1
    return 0
  replay_meta = i64[5]
  replayed = ffmh_replay(source_u,source_v,source_w,source_count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed != stats[5] || replay_meta[0] != 1 || replay_meta[1] != 1
    stats[10] = 0
    return 0
  stats[10] = 1
  replayed
