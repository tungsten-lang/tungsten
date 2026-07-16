# Endpoint-to-word compiler for a prescribed one-rank rectangular reduction.
#
# A k-to-(k-1) local replacement is lifted back to k terms by splitting one
# chosen target term.  The existing bidirectional exact BFS then compiles a
# state-dependent ordinary-flip word from the k source terms to that lifted
# target.  Merging the two split children performs the requested rank drop.
# This is the tensor analogue of a Rubik algorithm: the endpoint and cleanup
# are fixed first, while the middle word is resolved against the actual state.
#
# Recipe (32 words): the 28-word `rect_endpoint_path` recipe followed by
#   28 wrapper version, 29 target split index, 30 split axis, 31 split part.
# Search stats (20 words): the 16 base stats followed by
#   16 lifted local exact, 17 forward replay, 18 undo replay, 19 success.
# Replay meta (12 words): the eight base replay words followed by
#   8 cleanup legal, 9 final set match, 10 final local exact, 11 success.
#
# This module is offline.  A successful compile proves reachability of a
# supplied exact replacement; it does not itself discover or schedule one.

use rect_endpoint_path
use macro_holonomy

-> fferd_recipe_size() i64
  32

-> fferd_stats_size() i64
  20

-> fferd_meta_size() i64
  12

-> fferd_auto_stats_size() i64
  24

-> fferd_copy_prefix(source, dest, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest[i] = source[i]
    i += 1
  count

-> fferd_recipe_valid(recipe, source_count, target_count) (i64[] i64 i64) i64
  if recipe.size() < fferd_recipe_size() || recipe[28] != 1
    return 0
  if source_count < 2 || source_count > ffrep_max_count() || target_count != source_count - 1
    return 0
  if recipe[2] != source_count || recipe[3] != source_count
    return 0
  if recipe[29] < 0 || recipe[29] >= target_count || recipe[30] < 0 || recipe[30] > 2 || recipe[31] <= 0
    return 0
  ffrep_recipe_valid(recipe)

-> fferd_build_lift(target_u, target_v, target_w, target_count, recipe, lift_u, lift_v, lift_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  source_count = target_count + 1 ## i64
  if target_count < 1 || source_count > ffrep_max_count() || target_u.size() < target_count || target_v.size() < target_count || target_w.size() < target_count
    return 0
  if lift_u.size() < source_count || lift_v.size() < source_count || lift_w.size() < source_count
    return 0
  z = ffrep_copy_slot(target_u,target_v,target_w,0,target_count,lift_u,lift_v,lift_w,0) ## i64
  lifted = ffmh_split_labeled(lift_u,lift_v,lift_w,target_count,source_count,recipe[29],recipe[30],recipe[31]) ## i64
  if lifted != source_count
    return 0
  z = ffrep_sort_slot(lift_u,lift_v,lift_w,0,source_count)
  source_count

-> fferd_find_term(us, vs, ws, count, u, v, w, skip) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if i != skip && us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> fferd_split_children(target_u, target_v, target_w, recipe, child_u, child_v, child_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if child_u.size() < 2 || child_v.size() < 2 || child_w.size() < 2
    return 0
  source = recipe[29] ## i64
  axis = recipe[30] ## i64
  part = recipe[31] ## i64
  child_u[0] = target_u[source]
  child_v[0] = target_v[source]
  child_w[0] = target_w[source]
  child_u[1] = target_u[source]
  child_v[1] = target_v[source]
  child_w[1] = target_w[source]
  factor = ffmh_axis_get(target_u,target_v,target_w,source,axis) ## i64
  other = factor ^ part ## i64
  if factor == 0 || part == factor || other == 0
    return 0
  z = ffmh_axis_set(child_u,child_v,child_w,0,axis,part) ## i64
  z = ffmh_axis_set(child_u,child_v,child_w,1,axis,other)
  2

-> fferd_replay_forward(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if fferd_recipe_valid(recipe,source_count,target_count) == 0 || out_u.size() < target_count || out_v.size() < target_count || out_w.size() < target_count || meta.size() < fferd_meta_size()
    return 0
  z = ffrep_clear(meta,fferd_meta_size()) ## i64
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
    return 0
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,lift_u,lift_v,lift_w,source_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  work_u = i64[source_count]
  work_v = i64[source_count]
  work_w = i64[source_count]
  base_meta = i64[ffrep_replay_meta_size()]
  replayed = ffrep_replay_forward(source_u,source_v,source_w,source_count,lift_u,lift_v,lift_w,source_count,recipe,work_u,work_v,work_w,base_meta) ## i64
  if replayed != source_count
    return 0
  z = fferd_copy_prefix(base_meta,meta,ffrep_replay_meta_size())
  child_u = i64[2]
  child_v = i64[2]
  child_w = i64[2]
  if fferd_split_children(target_u,target_v,target_w,recipe,child_u,child_v,child_w) != 2
    return 0
  first = fferd_find_term(work_u,work_v,work_w,source_count,child_u[0],child_v[0],child_w[0],0-1) ## i64
  second = fferd_find_term(work_u,work_v,work_w,source_count,child_u[1],child_v[1],child_w[1],first) ## i64
  if first < 0 || second < 0
    return 0
  merged = ffmh_merge_labeled(work_u,work_v,work_w,source_count,first,second,recipe[30]) ## i64
  if merged != target_count
    return 0
  meta[8] = 1
  z = ffrep_sort_slot(work_u,work_v,work_w,0,target_count)
  if fftc_terms_same_set(work_u,work_v,work_w,target_count,target_u,target_v,target_w,target_count) != 1
    return 0
  meta[9] = 1
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,work_u,work_v,work_w,target_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[10] = 1
  z = ffrep_copy_slot(work_u,work_v,work_w,0,target_count,out_u,out_v,out_w,0)
  meta[11] = 1
  target_count

-> fferd_replay_undo(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if fferd_recipe_valid(recipe,source_count,target_count) == 0 || out_u.size() < source_count || out_v.size() < source_count || out_w.size() < source_count || meta.size() < fferd_meta_size()
    return 0
  z = ffrep_clear(meta,fferd_meta_size()) ## i64
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
    return 0
  base_meta = i64[ffrep_replay_meta_size()]
  undone = ffrep_replay_undo(source_u,source_v,source_w,source_count,lift_u,lift_v,lift_w,source_count,recipe,out_u,out_v,out_w,base_meta) ## i64
  if undone != source_count
    return 0
  z = fferd_copy_prefix(base_meta,meta,ffrep_replay_meta_size())
  if fftc_terms_same_set(out_u,out_v,out_w,source_count,source_u,source_v,source_w,source_count) != 1
    return 0
  meta[9] = 1
  if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,out_u,out_v,out_w,source_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[10] = 1
  meta[11] = 1
  source_count

-> fferd_search(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, udim, vdim, wdim, split_target, split_axis, split_part, max_depth, node_cap, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if source_count < 2 || source_count > ffrep_max_count() || target_count != source_count - 1
    return 0
  if recipe.size() < fferd_recipe_size() || stats.size() < fferd_stats_size()
    return 0
  if split_target < 0 || split_target >= target_count || split_axis < 0 || split_axis > 2 || split_part <= 0
    return 0
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  z = ffrep_fill(recipe,fferd_recipe_size(),0-1) ## i64
  z = ffrep_clear(stats,fferd_stats_size())
  recipe[0] = 1
  recipe[1] = 0
  recipe[2] = source_count
  recipe[3] = source_count
  recipe[4] = 0
  recipe[5] = udim
  recipe[6] = vdim
  recipe[7] = wdim
  recipe[28] = 1
  recipe[29] = split_target
  recipe[30] = split_axis
  recipe[31] = split_part
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
    return 0
  if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,lift_u,lift_v,lift_w,source_count,udim,vdim,wdim) != 1
    return 0
  stats[16] = 1
  if fftc_terms_same_set(source_u,source_v,source_w,source_count,lift_u,lift_v,lift_w,source_count) == 0
    base_recipe = i64[ffrep_recipe_size()]
    base_stats = i64[ffrep_stats_size()]
    path = ffrep_search_same_rank(source_u,source_v,source_w,source_count,lift_u,lift_v,lift_w,source_count,udim,vdim,wdim,max_depth,node_cap,base_recipe,base_stats) ## i64
    if path < 1
      return 0
    z = fferd_copy_prefix(base_recipe,recipe,ffrep_recipe_size())
    z = fferd_copy_prefix(base_stats,stats,ffrep_stats_size())
    recipe[28] = 1
    recipe[29] = split_target
    recipe[30] = split_axis
    recipe[31] = split_part
    stats[16] = 1
  replay_u = i64[target_count]
  replay_v = i64[target_count]
  replay_w = i64[target_count]
  replay_meta = i64[fferd_meta_size()]
  if fferd_replay_forward(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,replay_u,replay_v,replay_w,replay_meta) != target_count || replay_meta[11] != 1
    return 0
  stats[17] = 1
  undo_u = i64[source_count]
  undo_v = i64[source_count]
  undo_w = i64[source_count]
  if fferd_replay_undo(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,undo_u,undo_v,undo_w,replay_meta) != source_count || replay_meta[11] != 1
    return 0
  stats[18] = 1
  stats[19] = 1
  recipe[4] + 1

# Automatically propose the final merge scaffold.  Pairs already present in
# the source are tried first because they name a concrete cleanup door; if no
# such scaffold reaches the endpoint, source factor masks are tried as bounded
# target splits. Auto stats extend the selected 20-word search stats with:
#   20 candidates tried, 21 successful compiles, 22 fallback candidates,
#   23 source-pair cleanup candidates.
-> fferd_search_auto(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, udim, vdim, wdim, max_depth, node_cap, candidate_cap, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if recipe.size() < fferd_recipe_size() || stats.size() < fferd_auto_stats_size() || candidate_cap < 1 || candidate_cap > 4096
    return 0
  z = ffrep_clear(stats,fferd_auto_stats_size()) ## i64
  best = 0 ## i64
  tried = 0 ## i64
  hits = 0 ## i64
  fallback = 0 ## i64
  pair_candidates = 0 ## i64
  stop = 0 ## i64
  first = 0 ## i64
  while first < source_count-1 && tried < candidate_cap && stop == 0
    second = first + 1 ## i64
    while second < source_count && tried < candidate_cap && stop == 0
      axis = 0 ## i64
      while axis < 3 && tried < candidate_cap && stop == 0
        mergeable = 0 ## i64
        if axis == 0 && source_v[first] == source_v[second] && source_w[first] == source_w[second]
          mergeable = 1
        if axis == 1 && source_u[first] == source_u[second] && source_w[first] == source_w[second]
          mergeable = 1
        if axis == 2 && source_u[first] == source_u[second] && source_v[first] == source_v[second]
          mergeable = 1
        if mergeable == 1
          merged_u = source_u[first] ## i64
          merged_v = source_v[first] ## i64
          merged_w = source_w[first] ## i64
          part = ffmh_axis_get(source_u,source_v,source_w,first,axis) ## i64
          merged_factor = part ^ ffmh_axis_get(source_u,source_v,source_w,second,axis) ## i64
          if merged_factor != 0
            if axis == 0
              merged_u = merged_factor
            if axis == 1
              merged_v = merged_factor
            if axis == 2
              merged_w = merged_factor
            target_index = 0 ## i64
            while target_index < target_count && tried < candidate_cap && stop == 0
              if target_u[target_index] == merged_u && target_v[target_index] == merged_v && target_w[target_index] == merged_w
                tried += 1
                pair_candidates += 1
                trial_recipe = i64[fferd_recipe_size()]
                trial_stats = i64[fferd_stats_size()]
                found = fferd_search(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim,target_index,axis,part,max_depth,node_cap,trial_recipe,trial_stats) ## i64
                if found > 0
                  hits += 1
                  if best == 0 || found < best
                    best = found
                    z = fferd_copy_prefix(trial_recipe,recipe,fferd_recipe_size())
                    z = fferd_copy_prefix(trial_stats,stats,fferd_stats_size())
                  if best == 1
                    stop = 1
              target_index += 1
        axis += 1
      second += 1
    first += 1

  # A useful final split need not already occur as a source pair.  Reuse each
  # observed source factor as a bounded part proposal for every target/axis.
  target_index = 0
  while target_index < target_count && tried < candidate_cap && stop == 0
    axis = 0
    while axis < 3 && tried < candidate_cap && stop == 0
      factor = ffmh_axis_get(target_u,target_v,target_w,target_index,axis) ## i64
      width = udim ## i64
      if axis == 1
        width = vdim
      if axis == 2
        width = wdim
      source_index = 0 ## i64
      while source_index < source_count && tried < candidate_cap && stop == 0
        part = ffmh_axis_get(source_u,source_v,source_w,source_index,axis) ## i64
        if part != factor && ffrep_factor_fits(part,width) == 1 && (factor ^ part) != 0
          tried += 1
          fallback += 1
          trial_recipe = i64[fferd_recipe_size()]
          trial_stats = i64[fferd_stats_size()]
          found = fferd_search(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim,target_index,axis,part,max_depth,node_cap,trial_recipe,trial_stats) ## i64
          if found > 0
            hits += 1
            if best == 0 || found < best
              best = found
              z = fferd_copy_prefix(trial_recipe,recipe,fferd_recipe_size())
              z = fferd_copy_prefix(trial_stats,stats,fferd_stats_size())
            if best == 1
              stop = 1
        source_index += 1
      axis += 1
    target_index += 1
  stats[20] = tried
  stats[21] = hits
  stats[22] = fallback
  stats[23] = pair_candidates
  best
