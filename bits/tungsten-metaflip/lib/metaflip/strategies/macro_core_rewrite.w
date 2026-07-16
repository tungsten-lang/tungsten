# Constraint-directed exact word search for replacing a chosen local/core term.
#
# A split moves the local scheme onto its labelled R+1 shoulder.  Every edge is
# a legal pair flip, so the local tensor remains exact.  Unlike a fixed merge
# goal, the closing partner and axis are recomputed from each partial state.
# The close must absorb the chosen target label and the compacted endpoint may
# not contain the original target term.  This is the useful Rubik-like lesson:
# the next move and even the final constraint are state-dependent.
#
# Offline only.  Recipe layout matches macro_goal_beam (20 words).  Stats also
# use its 16-word layout; [4] counts target-merge-ready states, [14] is maximum
# target-label Hamming displacement, and [15] is minimum dynamic merge mismatch.

use macro_goal_beam

-> ffmcr_contains_term(us, vs, ws, offset, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if fftc_same_term(us[offset+i],vs[offset+i],ws[offset+i],u,v,w) == 1
      return 1
    i += 1
  0

-> ffmcr_target_distance(us, vs, ws, offset, target_label, target_u, target_v, target_w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  ffw_popcount(us[offset+target_label] ^ target_u) + ffw_popcount(vs[offset+target_label] ^ target_v) + ffw_popcount(ws[offset+target_label] ^ target_w)

# Return the best state-dependent partner/axis for absorbing target_label.
# out = [partner, axis, readiness, mismatch].  The direct setup inverse is not
# a useful core rewrite and is excluded even if a longer word returns to it.
-> ffmcr_best_merge(us, vs, ws, offset, count, target_label, split_source, split_axis, out) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[]) i64
  out[0] = 0 - 1
  out[1] = 0 - 1
  out[2] = 0
  out[3] = 1 << 30
  new_label = count - 1 ## i64
  best_score = 0 - 9223372036854775807 ## i64
  second = 0 ## i64
  while second < count
    if second != target_label
      axis = 0 ## i64
      while axis < 3
        direct_inverse = 0 ## i64
        if target_label == split_source && second == new_label && axis == split_axis
          direct_inverse = 1
        if direct_inverse == 0
          readiness = ffmgb_readiness(us,vs,ws,offset,target_label,second,axis) ## i64
          mismatch = ffmgb_mismatch_bits(us,vs,ws,offset,target_label,second,axis) ## i64
          score = readiness*1000000000 - mismatch*1000000 - second*4 - axis ## i64
          if score > best_score
            best_score = score
            out[0] = second
            out[1] = axis
            out[2] = readiness
            out[3] = mismatch
        axis += 1
    second += 1
  out[0]

-> ffmcr_score(us, vs, ws, offset, count, target_label, split_source, split_axis, active_mask, root_u, root_v, root_w, target_u, target_v, target_w, merge) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  z = ffmcr_best_merge(us,vs,ws,offset,count,target_label,split_source,split_axis,merge) ## i64
  readiness = merge[2] ## i64
  mismatch = merge[3] ## i64
  absent = 1 - ffmcr_contains_term(us,vs,ws,offset,count,target_u,target_v,target_w) ## i64
  displacement = ffmcr_target_distance(us,vs,ws,offset,target_label,target_u,target_v,target_w) ## i64
  pressure = ffmgb_target_pressure(us,vs,ws,offset,count,target_label,merge[0]) ## i64
  changed = ffmgb_changed_labels(us,vs,ws,offset,root_u,root_v,root_w,count) ## i64
  active = ffw_popcount(active_mask) ## i64
  density = ffmgb_slot_density(us,vs,ws,offset,count) ## i64
  readiness*1000000000000 + absent*100000000000 - mismatch*100000000 + displacement*1000000 + pressure*10000 + changed*100 + active*10 - density

# Mode 0 is objective-oriented (rank, density, distance). Mode 1 is the
# deliberately exploratory arm (rank, distance, density) used to detect doors
# the ordinary span-4 family cannot already express.
-> ffmcr_endpoint_better(rank, distance, density_delta, depth, selection_mode, stats) (i64 i64 i64 i64 i64 i64[]) i64
  if stats[7] == 0 || rank < stats[7]
    return 1
  if rank > stats[7]
    return 0
  if selection_mode != 0
    if distance > stats[8]
      return 1
    if distance < stats[8]
      return 0
  if density_delta < stats[9]
    return 1
  if density_delta > stats[9]
    return 0
  if selection_mode == 0
    if distance > stats[8]
      return 1
    if distance < stats[8]
      return 0
  if depth < stats[10]
    return 1
  0

-> ffmcr_replay(source_u, source_v, source_w, source_count, target_index, recipe, out_u, out_v, out_w, replay_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if target_index < 0 || target_index >= source_count
    return 0
  replayed = ffmgb_replay(source_u,source_v,source_w,source_count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed < 1
    return 0
  if ffmcr_contains_term(out_u,out_v,out_w,0,replayed,source_u[target_index],source_v[target_index],source_w[target_index]) != 0
    return 0
  replayed

-> ffmcr_search(source_u, source_v, source_w, source_count, target_index, split_source, split_axis, part, min_depth, max_depth, beam_width, selection_mode, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 2 || source_count > 8 || target_index < 0 || target_index >= source_count || split_source < 0 || split_source >= source_count || split_axis < 0 || split_axis > 2 || part <= 0
    return 0
  shoulder_count = source_count + 1 ## i64
  if min_depth < 1 || max_depth < min_depth || max_depth > ffmgb_max_depth() || beam_width < 1 || beam_width > 512
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

  target_u = source_u[target_index] ## i64
  target_v = source_v[target_index] ## i64
  target_w = source_w[target_index] ## i64
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
  beam_active[0] = (1 << target_index) | (1 << split_source) | (1 << source_count)
  beam_last[0] = 0 - 1
  z = ffmgb_seen_or_add(visited_key1,visited_key2,visited_used,visited_u,visited_v,visited_w,table_mask,root_u,root_v,root_w,0,shoulder_count,hash[0],hash[1],1)
  stats[13] = 1
  beam_count = 1 ## i64
  stats[11] = 1
  source_density = fftc_density(source_u,source_v,source_w,source_count) ## i64
  code_count = fftc_code_count(shoulder_count) ## i64
  pair = i64[3]
  merge = i64[4]
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
                score = ffmcr_score(child_u,child_v,child_w,0,shoulder_count,target_index,split_source,split_axis,child_active,root_u,root_v,root_w,target_u,target_v,target_w,merge) ## i64
                slot = next_count ## i64
                accepted = 1 ## i64
                if next_count >= beam_width
                  worst = 0 ## i64
                  scan = 1
                  while scan < next_count
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
      displacement = ffmcr_target_distance(beam_u,beam_v,beam_w,offset,target_index,target_u,target_v,target_w) ## i64
      if displacement > stats[14]
        stats[14] = displacement
      z = ffmcr_best_merge(beam_u,beam_v,beam_w,offset,shoulder_count,target_index,split_source,split_axis,merge)
      if merge[3] < stats[15]
        stats[15] = merge[3]
      if depth >= min_depth && merge[2] == 2
        stats[4] += 1
        # More than one target close can be ready in the same partial state.
        second = 0 ## i64
        while second < shoulder_count
          if second != target_index
            axis = 0 ## i64
            while axis < 3
              direct_inverse = 0 ## i64
              if target_index == split_source && second == source_count && axis == split_axis
                direct_inverse = 1
              if direct_inverse == 0 && ffmgb_readiness(beam_u,beam_v,beam_w,offset,target_index,second,axis) == 2
                z = ffmgb_copy_slot(beam_u,beam_v,beam_w,offset,shoulder_count,merge_u,merge_v,merge_w,0)
                merged = ffmh_merge_labeled(merge_u,merge_v,merge_w,shoulder_count,target_index,second,axis) ## i64
                if merged > 0
                  compacted = ffmh_compact(merge_u,merge_v,merge_w,merged,compact_u,compact_v,compact_w) ## i64
                  if compacted > 0
                    distance = ffmh_distance(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) ## i64
                    target_absent = 1 - ffmcr_contains_term(compact_u,compact_v,compact_w,0,compacted,target_u,target_v,target_w) ## i64
                    if distance > 0 && target_absent == 1
                      stats[5] += 1
                      density_delta = fftc_density(compact_u,compact_v,compact_w,compacted) - source_density ## i64
                      if ffmh_local_exact(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) == 1
                        stats[6] += 1
                        if ffmcr_endpoint_better(compacted,distance,density_delta,depth,selection_mode,stats) == 1
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
                          recipe[14] = target_index
                          recipe[15] = second
                          recipe[16] = axis
                          recipe[17] = compacted
                          recipe[18] = distance
                          recipe[19] = density_delta
                          stats[7] = compacted
                          stats[8] = distance
                          stats[9] = density_delta
                          stats[10] = depth
              axis += 1
          second += 1
      slot += 1

  if stats[7] < 1
    return 0
  replay_meta = i64[4]
  replayed = ffmcr_replay(source_u,source_v,source_w,source_count,target_index,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if replayed != stats[7] || replay_meta[0] != 1 || replay_meta[1] != 1
    stats[12] = 0
    return 0
  stats[12] = 1
  replayed
