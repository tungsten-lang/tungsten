# Goal-directed beam search on the labelled R+1 split shoulder graph.
#
# A setup split creates two labelled terms. Every graph edge is one connected
# ordered pair flip, hence preserves the exact local tensor. Unlike the older
# depth-four DFS holonomy enumerator, this search is told which *alternate*
# label pair should become mergeable on which axis and uses the two remaining
# factor equalities as its heuristic. Retained states are exact-deduplicated by
# a canonical labelled hash table, so longer searches do not spend their beam
# budget walking short involutive cycles.
#
# This module is an offline strategy only. It is intentionally not imported by
# the fleet or GPU portfolio; real-frontier evidence must show both a genuine
# beyond-span-4 endpoint and useful matched continuation before production use.
#
# `ffmgb_search_annihilation` is the rank-drop endpoint mode.  It asks a chosen
# shoulder pair to agree on all three factors, then parity-annihilates the two
# identical labels.  Starting from an R+1 split shoulder, that close removes
# two labels and therefore returns at rank at most R-1.  The ordinary
# `ffmgb_search` merge goal remains unchanged.
#
# Fixed recipe layout (20 words):
#   [0] split source, [1] split axis, [2] split part, [3] path depth
#   [4..13] ordered pair-flip codes (unused entries are -1)
#   [14] merge first, [15] merge second, [16] merge axis
#   [17] endpoint rank, [18] endpoint distance, [19] density delta
#
# Stats (16 words):
#   [0] codes considered, [1] legal connected edges, [2] visited revisits,
#   [3] states retained, [4] merge-ready states, [5] changed closes,
#   [6] exact closes, [7] best rank, [8] best distance,
#   [9] best density delta, [10] best depth, [11] largest beam,
#   [12] replay exact, [13] canonical states visited,
#   [14] maximum readiness, [15] minimum mismatch bits.

use macro_holonomy

-> ffmgb_recipe_size() i64
  20

-> ffmgb_stats_size() i64
  16

-> ffmgb_max_depth() i64
  10

-> ffmgb_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffmgb_copy_slot(source_u, source_v, source_w, source_offset, count, dest_u, dest_v, dest_w, dest_offset) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest_u[dest_offset+i] = source_u[source_offset+i]
    dest_v[dest_offset+i] = source_v[source_offset+i]
    dest_w[dest_offset+i] = source_w[source_offset+i]
    i += 1
  count

-> ffmgb_slot_equal(left_u, left_v, left_w, left_offset, right_u, right_v, right_w, right_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if left_u[left_offset+i] != right_u[right_offset+i] || left_v[left_offset+i] != right_v[right_offset+i] || left_w[left_offset+i] != right_w[right_offset+i]
      return 0
    i += 1
  1

# Two independent order-sensitive digests. Label position is deliberately part
# of the key: pair-flip codes and the requested closing labels are positional.
-> ffmgb_label_hash(us, vs, ws, offset, count, out) (i64[] i64[] i64[] i64 i64 i64[]) i64
  h1 = 0 ## i64
  h2 = 0 ## i64
  i = 0 ## i64
  while i < count
    label = i + 1 ## i64
    h1 = h1 ^ ffw_term_zobrist(us[offset+i] ^ label,vs[offset+i],ws[offset+i])
    h2 = h2 ^ ffw_term_zobrist(us[offset+i],vs[offset+i] ^ (label << 8),ws[offset+i] ^ (label << 16))
    i += 1
  out[0] = h1 & 9223372036854775807
  out[1] = h2 & 9223372036854775807
  1

# Exact open-addressed visited set. Hash equality is only a prefilter; a rare
# collision probes onward after comparing the full labelled state.
-> ffmgb_seen_or_add(keys1, keys2, used, table_u, table_v, table_w, mask, state_u, state_v, state_w, state_offset, count, key1, key2, add) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  index = (key1 ^ (key2 >> 17) ^ (key1 >> 41)) & mask ## i64
  probes = 0 ## i64
  while probes <= mask
    if used[index] == 0
      if add != 0
        used[index] = 1
        keys1[index] = key1
        keys2[index] = key2
        z = ffmgb_copy_slot(state_u,state_v,state_w,state_offset,count,table_u,table_v,table_w,index*count) ## i64
      return 0
    if keys1[index] == key1 && keys2[index] == key2
      if ffmgb_slot_equal(state_u,state_v,state_w,state_offset,table_u,table_v,table_w,index*count,count) == 1
        return 1
    index = (index + 1) & mask
    probes += 1
  # A full table conservatively counts as seen. Search allocates at least four
  # buckets per possible retained state, so this is a corruption guard only.
  1

-> ffmgb_readiness(us, vs, ws, offset, first, second, merge_axis) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  ready = 0 ## i64
  if merge_axis != 0 && us[offset+first] == us[offset+second]
    ready += 1
  if merge_axis != 1 && vs[offset+first] == vs[offset+second]
    ready += 1
  if merge_axis != 2 && ws[offset+first] == ws[offset+second]
    ready += 1
  ready

-> ffmgb_mismatch_bits(us, vs, ws, offset, first, second, merge_axis) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  mismatch = 0 ## i64
  if merge_axis != 0
    mismatch += ffw_popcount(us[offset+first] ^ us[offset+second])
  if merge_axis != 1
    mismatch += ffw_popcount(vs[offset+first] ^ vs[offset+second])
  if merge_axis != 2
    mismatch += ffw_popcount(ws[offset+first] ^ ws[offset+second])
  mismatch

# Count pair-flip doors incident to either requested merge label. This rewards
# useful setup states that can still manipulate the goal rather than merely
# matching one factor by accident.
-> ffmgb_target_pressure(us, vs, ws, offset, count, first, second) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  pressure = 0 ## i64
  target_slot = 0 ## i64
  while target_slot < 2
    target = first ## i64
    if target_slot == 1
      target = second
    i = 0 ## i64
    while i < count
      if i != target
        if us[offset+target] == us[offset+i]
          pressure += 1
        if vs[offset+target] == vs[offset+i]
          pressure += 1
        if ws[offset+target] == ws[offset+i]
          pressure += 1
      i += 1
    target_slot += 1
  pressure

-> ffmgb_changed_labels(us, vs, ws, offset, root_u, root_v, root_w, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  changed = 0 ## i64
  i = 0 ## i64
  while i < count
    if us[offset+i] != root_u[i] || vs[offset+i] != root_v[i] || ws[offset+i] != root_w[i]
      changed += 1
    i += 1
  changed

-> ffmgb_slot_density(us, vs, ws, offset, count) (i64[] i64[] i64[] i64 i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < count
    density += ffw_popcount(us[offset+i]) + ffw_popcount(vs[offset+i]) + ffw_popcount(ws[offset+i])
    i += 1
  density

# Beam/A* heuristic: exact merge readiness dominates, then Hamming distance to
# the two required equalities, available target doors, labelled novelty, and
# connected-component coverage. Density breaks otherwise comparable ties.
-> ffmgb_score(us, vs, ws, offset, count, first, second, merge_axis, active_mask, root_u, root_v, root_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  readiness = ffmgb_readiness(us,vs,ws,offset,first,second,merge_axis) ## i64
  mismatch = ffmgb_mismatch_bits(us,vs,ws,offset,first,second,merge_axis) ## i64
  pressure = ffmgb_target_pressure(us,vs,ws,offset,count,first,second) ## i64
  changed = ffmgb_changed_labels(us,vs,ws,offset,root_u,root_v,root_w,count) ## i64
  active = ffw_popcount(active_mask) ## i64
  density = ffmgb_slot_density(us,vs,ws,offset,count) ## i64
  readiness*1000000000000 - mismatch*100000000 + pressure*1000000 + changed*10000 + active*100 - density

-> ffmgb_lex_before(left_u, left_v, left_w, left_offset, right_u, right_v, right_w, right_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if left_u[left_offset+i] < right_u[right_offset+i]
      return 1
    if left_u[left_offset+i] > right_u[right_offset+i]
      return 0
    if left_v[left_offset+i] < right_v[right_offset+i]
      return 1
    if left_v[left_offset+i] > right_v[right_offset+i]
      return 0
    if left_w[left_offset+i] < right_w[right_offset+i]
      return 1
    if left_w[left_offset+i] > right_w[right_offset+i]
      return 0
    i += 1
  0

-> ffmgb_state_better(left_score, left_h1, left_h2, left_u, left_v, left_w, left_offset, right_score, right_h1, right_h2, right_u, right_v, right_w, right_offset, count) (i64 i64 i64 i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64 i64) i64
  if left_score > right_score
    return 1
  if left_score < right_score
    return 0
  if left_h1 < right_h1
    return 1
  if left_h1 > right_h1
    return 0
  if left_h2 < right_h2
    return 1
  if left_h2 > right_h2
    return 0
  ffmgb_lex_before(left_u,left_v,left_w,left_offset,right_u,right_v,right_w,right_offset,count)

-> ffmgb_endpoint_better(rank, distance, density_delta, depth, stats) (i64 i64 i64 i64 i64[]) i64
  if stats[7] == 0 || rank < stats[7]
    return 1
  if rank > stats[7]
    return 0
  if distance > stats[8]
    return 1
  if distance < stats[8]
    return 0
  if density_delta < stats[9]
    return 1
  if density_delta > stats[9]
    return 0
  if depth < stats[10]
    return 1
  0

-> ffmgb_replay(source_u, source_v, source_w, source_count, recipe, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 8 || recipe.size() < ffmgb_recipe_size() || replay_meta.size() < 4
    return 0
  shoulder_count = source_count + 1 ## i64
  if out_u.size() < shoulder_count || out_v.size() < shoulder_count || out_w.size() < shoulder_count
    return 0
  us = i64[shoulder_count]
  vs = i64[shoulder_count]
  ws = i64[shoulder_count]
  z = ffmh_copy(source_u,source_v,source_w,source_count,us,vs,ws) ## i64
  count = ffmh_split_labeled(us,vs,ws,source_count,shoulder_count,recipe[0],recipe[1],recipe[2]) ## i64
  if count != shoulder_count
    return 0
  depth = recipe[3] ## i64
  if depth < 1 || depth > ffmgb_max_depth()
    return 0
  step = 0 ## i64
  while step < depth
    if fftc_apply_code(us,vs,ws,count,recipe[4+step],0-1) != 1
      return 0
    step += 1
  merged = ffmh_merge_labeled(us,vs,ws,count,recipe[14],recipe[15],recipe[16]) ## i64
  if merged < 1
    return 0
  compacted = ffmh_compact(us,vs,ws,merged,out_u,out_v,out_w) ## i64
  if compacted < 1 || compacted != recipe[17]
    return 0
  exact = ffmh_local_exact(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted) ## i64
  distance = ffmh_distance(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted) ## i64
  z = ffmgb_clear(replay_meta,4)
  replay_meta[0] = exact
  if distance > 0
    replay_meta[1] = 1
  replay_meta[2] = distance
  replay_meta[3] = fftc_density(out_u,out_v,out_w,compacted) - fftc_density(source_u,source_v,source_w,source_count)
  if exact != 1 || distance < 1 || distance != recipe[18] || replay_meta[3] != recipe[19]
    return 0
  compacted

-> ffmgb_search(source_u, source_v, source_w, source_count, split_source, split_axis, part, merge_first, merge_second, merge_axis, min_depth, max_depth, beam_width, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 8 || split_source < 0 || split_source >= source_count || split_axis < 0 || split_axis > 2 || part <= 0
    return 0
  shoulder_count = source_count + 1 ## i64
  # Axis three is an internal endpoint predicate, not a tensor axis: all three
  # factors must match so the pair can annihilate.  Replay records the concrete
  # axis-zero duplicate close, keeping the recipe format backward-compatible.
  if merge_first < 0 || merge_second < 0 || merge_first >= shoulder_count || merge_second >= shoulder_count || merge_first == merge_second || merge_axis < 0 || merge_axis > 3
    return 0
  direct_setup_merge = 0 ## i64
  if merge_axis == split_axis
    if (merge_first == split_source && merge_second == source_count) || (merge_second == split_source && merge_first == source_count)
      direct_setup_merge = 1
  if direct_setup_merge != 0 || min_depth < 1 || max_depth < min_depth || max_depth > ffmgb_max_depth() || beam_width < 1 || beam_width > 512
    return 0
  if out_u.size() < shoulder_count || out_v.size() < shoulder_count || out_w.size() < shoulder_count || recipe.size() < ffmgb_recipe_size() || stats.size() < ffmgb_stats_size()
    return 0

  z = ffmgb_clear(recipe,ffmgb_recipe_size()) ## i64
  z = ffmgb_clear(stats,ffmgb_stats_size())
  code_slot = 4 ## i64
  while code_slot < 14
    recipe[code_slot] = 0 - 1
    code_slot += 1
  stats[15] = 1 << 30

  goal_readiness = 2 ## i64
  endpoint_axis = merge_axis ## i64
  if merge_axis == 3
    goal_readiness = 3
    endpoint_axis = 0

  root_u = i64[shoulder_count]
  root_v = i64[shoulder_count]
  root_w = i64[shoulder_count]
  z = ffmh_copy(source_u,source_v,source_w,source_count,root_u,root_v,root_w)
  if ffmh_split_labeled(root_u,root_v,root_w,source_count,shoulder_count,split_source,split_axis,part) != shoulder_count
    return 0

  table_size = 16 ## i64
  wanted_table = beam_width * (max_depth + 1) * 4 ## i64
  while table_size < wanted_table
    table_size *= 2
  table_mask = table_size - 1 ## i64
  visited_key1 = i64[table_size]
  visited_key2 = i64[table_size]
  visited_used = i64[table_size]
  visited_u = i64[table_size*shoulder_count]
  visited_v = i64[table_size*shoulder_count]
  visited_w = i64[table_size*shoulder_count]

  beam_u = i64[beam_width*shoulder_count]
  beam_v = i64[beam_width*shoulder_count]
  beam_w = i64[beam_width*shoulder_count]
  beam_h1 = i64[beam_width]
  beam_h2 = i64[beam_width]
  beam_active = i64[beam_width]
  beam_last = i64[beam_width]
  beam_paths = i64[beam_width*ffmgb_max_depth()]
  z = ffmgb_copy_slot(root_u,root_v,root_w,0,shoulder_count,beam_u,beam_v,beam_w,0)
  hash = i64[2]
  z = ffmgb_label_hash(root_u,root_v,root_w,0,shoulder_count,hash)
  beam_h1[0] = hash[0]
  beam_h2[0] = hash[1]
  beam_active[0] = (1 << split_source) | (1 << source_count)
  beam_last[0] = 0 - 1
  z = ffmgb_seen_or_add(visited_key1,visited_key2,visited_used,visited_u,visited_v,visited_w,table_mask,root_u,root_v,root_w,0,shoulder_count,hash[0],hash[1],1)
  stats[13] = 1
  beam_count = 1 ## i64
  stats[11] = 1
  source_density = fftc_density(source_u,source_v,source_w,source_count) ## i64
  code_count = fftc_code_count(shoulder_count) ## i64
  pair = i64[3]
  child_u = i64[shoulder_count]
  child_v = i64[shoulder_count]
  child_w = i64[shoulder_count]
  merge_u = i64[shoulder_count]
  merge_v = i64[shoulder_count]
  merge_w = i64[shoulder_count]
  compact_u = i64[shoulder_count]
  compact_v = i64[shoulder_count]
  compact_w = i64[shoulder_count]

  depth = 0 ## i64
  while depth < max_depth && beam_count > 0
    next_u = i64[beam_width*shoulder_count]
    next_v = i64[beam_width*shoulder_count]
    next_w = i64[beam_width*shoulder_count]
    next_h1 = i64[beam_width]
    next_h2 = i64[beam_width]
    next_scores = i64[beam_width]
    next_active = i64[beam_width]
    next_last = i64[beam_width]
    next_paths = i64[beam_width*ffmgb_max_depth()]
    next_count = 0 ## i64
    parent = 0 ## i64
    while parent < beam_count
      parent_offset = parent * shoulder_count ## i64
      code = 0 ## i64
      while code < code_count
        stats[0] += 1
        connected = 0 ## i64
        if code != beam_last[parent] && ffmh_decode_code(code,shoulder_count,pair) == 1
          pair_mask = (1 << pair[0]) | (1 << pair[1]) ## i64
          if (pair_mask & beam_active[parent]) != 0
            connected = 1
        if connected == 1
          z = ffmgb_copy_slot(beam_u,beam_v,beam_w,parent_offset,shoulder_count,child_u,child_v,child_w,0)
          if fftc_apply_code(child_u,child_v,child_w,shoulder_count,code,0-1) == 1
            stats[1] += 1
            z = ffmgb_label_hash(child_u,child_v,child_w,0,shoulder_count,hash)
            seen = ffmgb_seen_or_add(visited_key1,visited_key2,visited_used,visited_u,visited_v,visited_w,table_mask,child_u,child_v,child_w,0,shoulder_count,hash[0],hash[1],0) ## i64
            if seen != 0
              stats[2] += 1
            if seen == 0
              duplicate = 0 ## i64
              scan = 0 ## i64
              while scan < next_count && duplicate == 0
                if next_h1[scan] == hash[0] && next_h2[scan] == hash[1]
                  if ffmgb_slot_equal(child_u,child_v,child_w,0,next_u,next_v,next_w,scan*shoulder_count,shoulder_count) == 1
                    duplicate = 1
                scan += 1
              if duplicate == 0
                child_active = beam_active[parent] | ((1 << pair[0]) | (1 << pair[1])) ## i64
                score = ffmgb_score(child_u,child_v,child_w,0,shoulder_count,merge_first,merge_second,merge_axis,child_active,root_u,root_v,root_w) ## i64
                slot = next_count ## i64
                accepted = 1 ## i64
                if next_count >= beam_width
                  worst = 0 ## i64
                  scan = 1
                  while scan < next_count
                    # If the current worst is better than this slot, this slot
                    # is the new deterministic worst.
                    if ffmgb_state_better(next_scores[worst],next_h1[worst],next_h2[worst],next_u,next_v,next_w,worst*shoulder_count,next_scores[scan],next_h1[scan],next_h2[scan],next_u,next_v,next_w,scan*shoulder_count,shoulder_count) == 1
                      worst = scan
                    scan += 1
                  if ffmgb_state_better(score,hash[0],hash[1],child_u,child_v,child_w,0,next_scores[worst],next_h1[worst],next_h2[worst],next_u,next_v,next_w,worst*shoulder_count,shoulder_count) == 1
                    slot = worst
                  else
                    accepted = 0
                if accepted == 1
                  z = ffmgb_copy_slot(child_u,child_v,child_w,0,shoulder_count,next_u,next_v,next_w,slot*shoulder_count)
                  next_h1[slot] = hash[0]
                  next_h2[slot] = hash[1]
                  next_scores[slot] = score
                  next_active[slot] = child_active
                  next_last[slot] = code
                  pi = 0 ## i64
                  while pi < depth
                    next_paths[slot*ffmgb_max_depth()+pi] = beam_paths[parent*ffmgb_max_depth()+pi]
                    pi += 1
                  next_paths[slot*ffmgb_max_depth()+depth] = code
                  if next_count < beam_width
                    next_count += 1
                  stats[3] += 1
        code += 1
      parent += 1

    beam_u = next_u
    beam_v = next_v
    beam_w = next_w
    beam_h1 = next_h1
    beam_h2 = next_h2
    beam_active = next_active
    beam_last = next_last
    beam_paths = next_paths
    beam_count = next_count
    depth += 1
    if beam_count > stats[11]
      stats[11] = beam_count

    slot = 0 ## i64
    while slot < beam_count
      offset = slot * shoulder_count ## i64
      existed = ffmgb_seen_or_add(visited_key1,visited_key2,visited_used,visited_u,visited_v,visited_w,table_mask,beam_u,beam_v,beam_w,offset,shoulder_count,beam_h1[slot],beam_h2[slot],1) ## i64
      if existed == 0
        stats[13] += 1
      readiness = ffmgb_readiness(beam_u,beam_v,beam_w,offset,merge_first,merge_second,merge_axis) ## i64
      mismatch = ffmgb_mismatch_bits(beam_u,beam_v,beam_w,offset,merge_first,merge_second,merge_axis) ## i64
      if readiness > stats[14]
        stats[14] = readiness
      if mismatch < stats[15]
        stats[15] = mismatch
      if depth >= min_depth && readiness == goal_readiness
        stats[4] += 1
        z = ffmgb_copy_slot(beam_u,beam_v,beam_w,offset,shoulder_count,merge_u,merge_v,merge_w,0)
        merged = ffmh_merge_labeled(merge_u,merge_v,merge_w,shoulder_count,merge_first,merge_second,endpoint_axis) ## i64
        if merged > 0
          compacted = ffmh_compact(merge_u,merge_v,merge_w,merged,compact_u,compact_v,compact_w) ## i64
          if compacted > 0
            distance = ffmh_distance(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) ## i64
            if distance > 0
              stats[5] += 1
              density_delta = fftc_density(compact_u,compact_v,compact_w,compacted) - source_density ## i64
              if ffmh_local_exact(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) == 1
                stats[6] += 1
                if ffmgb_endpoint_better(compacted,distance,density_delta,depth,stats) == 1
                  z = ffmh_copy(compact_u,compact_v,compact_w,compacted,out_u,out_v,out_w)
                  recipe[0] = split_source
                  recipe[1] = split_axis
                  recipe[2] = part
                  recipe[3] = depth
                  pi = 0
                  while pi < ffmgb_max_depth()
                    recipe[4+pi] = 0 - 1
                    if pi < depth
                      recipe[4+pi] = beam_paths[slot*ffmgb_max_depth()+pi]
                    pi += 1
                  recipe[14] = merge_first
                  recipe[15] = merge_second
                  recipe[16] = endpoint_axis
                  recipe[17] = compacted
                  recipe[18] = distance
                  recipe[19] = density_delta
                  stats[7] = compacted
                  stats[8] = distance
                  stats[9] = density_delta
                  stats[10] = depth
      slot += 1

  if stats[7] < 1
    return 0
  replay_meta = i64[4]
  replayed = ffmgb_replay(source_u,source_v,source_w,source_count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed != stats[7] || replay_meta[0] != 1 || replay_meta[1] != 1
    stats[12] = 0
    return 0
  stats[12] = 1
  replayed

# Rubik-style targeted rank drop: split/setup, a bounded exact shoulder word,
# then duplicate-pair cancellation.  This is discovery, unlike catalyst lift
# (which requires the lower-rank endpoint up front), and remains offline.
-> ffmgb_search_annihilation(source_u, source_v, source_w, source_count, split_source, split_axis, part, duplicate_first, duplicate_second, min_depth, max_depth, beam_width, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  result = ffmgb_search(source_u,source_v,source_w,source_count,split_source,split_axis,part,duplicate_first,duplicate_second,3,min_depth,max_depth,beam_width,out_u,out_v,out_w,recipe,stats) ## i64
  if result < 1 || result >= source_count
    return 0
  result
