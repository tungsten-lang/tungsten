# Offline target-directed double-annihilation macro.
#
# This is the coupled rank-two analogue of the single duplicate close in
# `macro_goal_beam`:
#
#   setup:   split two distinct source labels (R -> R+2)
#   trigger: follow a bounded state-dependent word of exact pair flips
#   cleanup: cancel two prescribed duplicate terms (R+2 -> R-2)
#
# The cleanup goals are concrete rank-one triples, not merely a density score.
# Search may also discover the first two-doublet endpoint in deterministic BFS
# order, but the retained recipe always records the concrete prescribed goals.
# Canonical sorting after every edge makes the search label-independent; both
# forward and reverse transition codes are resolved against the state where
# they are replayed.  Every prefix is independently shape-gated.
#
# This is deliberately an offline prototype.  It is not imported by a fleet or
# kernel pool and has a hard nine-label, depth-ten, 65,536-node envelope.
#
# Setup (6 words): source/axis/part for each split.
# Goals (6 words): U/V/W triples C and D; the endpoint must contain exactly
# two copies of C and exactly two copies of D, with C != D.
# Limits (3 words): minimum depth, maximum depth, node cap.
# Shape (3 words): U/V/W factor bit widths.
#
# Recipe (72 words):
#   0 version, 1 source count, 2..7 setup, 8 depth,
#   9..18 forward codes, 19..28 reverse codes,
#   29..34 cleanup goals, 35 result count, 36 distance,
#   37 density delta, 38..40 shape, 41 success,
#   42..68 canonical pre-close terms (nine interleaved triples).
#
# Stats (20 words): nodes, codes, legal edges, revisits, capped, states scanned,
# goal states, exact closes, depth, result count, forward replay, undo replay,
# input fit/exact, maximum built depth, prescribed mode, distance, density delta,
# root goal-ready, retained node, success.

use macro_holonomy
use rect_endpoint_path

-> ffmda_recipe_size() i64
  72

-> ffmda_stats_size() i64
  20

-> ffmda_replay_meta_size() i64
  8

-> ffmda_max_count() i64
  9

-> ffmda_max_depth() i64
  10

-> ffmda_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffmda_goal_distinct(goals) (i64[]) i64
  if goals.size() < 6
    return 0
  i = 0 ## i64
  while i < 6
    if goals[i] <= 0
      return 0
    i += 1
  if goals[0] == goals[3] && goals[1] == goals[4] && goals[2] == goals[5]
    return 0
  1

-> ffmda_term_equal(us, vs, ws, offset, index, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if us[offset+index] == u && vs[offset+index] == v && ws[offset+index] == w
    return 1
  0

-> ffmda_occurrences(us, vs, ws, offset, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    found += ffmda_term_equal(us,vs,ws,offset,i,u,v,w)
    i += 1
  found

-> ffmda_duplicate_labels(us, vs, ws, offset, count) (i64[] i64[] i64[] i64 i64) i64
  duplicate_labels = 0 ## i64
  scan = 0 ## i64
  while scan < count
    occurrences = ffmda_occurrences(us,vs,ws,offset,count,us[offset+scan],vs[offset+scan],ws[offset+scan]) ## i64
    if occurrences > 1
      duplicate_labels += 1
    scan += 1
  duplicate_labels

# Return concrete goals for the first state containing exactly two distinct
# doublets and no additional parity cancellation.  Canonical ordering makes
# this deterministic.
-> ffmda_find_goals(us, vs, ws, offset, count, goals) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if goals.size() < 6 || count < 4
    return 0
  first = 0 ## i64
  while first < count
    cu = us[offset+first] ## i64
    cv = vs[offset+first] ## i64
    cw = ws[offset+first] ## i64
    if ffmda_occurrences(us,vs,ws,offset,count,cu,cv,cw) == 2
      second = first + 1 ## i64
      while second < count
        du = us[offset+second] ## i64
        dv = vs[offset+second] ## i64
        dw = ws[offset+second] ## i64
        if (cu != du || cv != dv || cw != dw) && ffmda_occurrences(us,vs,ws,offset,count,du,dv,dw) == 2
          # Exactly four labels must participate in duplicate classes.
          if ffmda_duplicate_labels(us,vs,ws,offset,count) == 4
            goals[0] = cu
            goals[1] = cv
            goals[2] = cw
            goals[3] = du
            goals[4] = dv
            goals[5] = dw
            return 1
        second += 1
    first += 1
  0

-> ffmda_goal_hit(us, vs, ws, offset, count, goals) (i64[] i64[] i64[] i64 i64 i64[]) i64
  if ffmda_goal_distinct(goals) == 0
    return 0
  if ffmda_occurrences(us,vs,ws,offset,count,goals[0],goals[1],goals[2]) != 2
    return 0
  if ffmda_occurrences(us,vs,ws,offset,count,goals[3],goals[4],goals[5]) != 2
    return 0
  if ffmda_duplicate_labels(us,vs,ws,offset,count) != 4
    return 0
  1

-> ffmda_recipe_goal(recipe, goals) (i64[] i64[]) i64
  i = 0 ## i64
  while i < 6
    goals[i] = recipe[29+i]
    i += 1
  1

-> ffmda_store_preclose(us, vs, ws, offset, count, recipe) (i64[] i64[] i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < ffmda_max_count()
    recipe[42+i*3] = 0
    recipe[43+i*3] = 0
    recipe[44+i*3] = 0
    if i < count
      recipe[42+i*3] = us[offset+i]
      recipe[43+i*3] = vs[offset+i]
      recipe[44+i*3] = ws[offset+i]
    i += 1
  count

-> ffmda_preclose_equal(us, vs, ws, offset, count, recipe) (i64[] i64[] i64[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < count
    if us[offset+i] != recipe[42+i*3] || vs[offset+i] != recipe[43+i*3] || ws[offset+i] != recipe[44+i*3]
      return 0
    i += 1
  1

-> ffmda_build_root(source_u, source_v, source_w, source_count, setup, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  shoulder_count = source_count + 2 ## i64
  if source_count < 2 || shoulder_count > ffmda_max_count() || setup.size() < 6
    return 0
  if setup[0] < 0 || setup[0] >= source_count || setup[3] < 0 || setup[3] >= source_count || setup[0] == setup[3]
    return 0
  z = ffmh_copy(source_u,source_v,source_w,source_count,out_u,out_v,out_w) ## i64
  count = ffmh_split_labeled(out_u,out_v,out_w,source_count,shoulder_count,setup[0],setup[1],setup[2]) ## i64
  if count != source_count + 1
    return 0
  count = ffmh_split_labeled(out_u,out_v,out_w,count,shoulder_count,setup[3],setup[4],setup[5])
  if count != shoulder_count
    return 0
  count

# Convert a BFS parent chain into separately state-resolved forward and reverse
# words.  `path[0]` is the root and `path[depth]` is the retained endpoint.
-> ffmda_compile_path(states_u, states_v, states_w, parents, count, node, depth, recipe) (i64[] i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  path = i64[ffmda_max_depth()+1]
  cursor = node ## i64
  slot = depth ## i64
  while slot >= 0
    path[slot] = cursor
    if slot > 0
      cursor = parents[cursor]
      if cursor < 0
        return 0
    slot -= 1
  i = 0 ## i64
  while i < ffmda_max_depth()
    recipe[9+i] = 0 - 1
    recipe[19+i] = 0 - 1
    i += 1
  step = 0
  while step < depth
    forward = ffrep_find_transition(states_u,states_v,states_w,path[step]*count,states_u,states_v,states_w,path[step+1]*count,count) ## i64
    reverse = ffrep_find_transition(states_u,states_v,states_w,path[depth-step]*count,states_u,states_v,states_w,path[depth-step-1]*count,count) ## i64
    if forward < 0 || reverse < 0
      return 0
    recipe[9+step] = forward
    recipe[19+step] = reverse
    step += 1
  1

-> ffmda_recipe_valid(recipe) (i64[]) i64
  if recipe.size() < ffmda_recipe_size() || recipe[0] != 1 || recipe[41] != 1
    return 0
  if recipe[1] < 2 || recipe[1] + 2 > ffmda_max_count() || recipe[8] < 1 || recipe[8] > ffmda_max_depth()
    return 0
  goals = i64[6]
  z = ffmda_recipe_goal(recipe,goals) ## i64
  ffmda_goal_distinct(goals)

-> ffmda_replay_forward(source_u, source_v, source_w, source_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ffmda_recipe_valid(recipe) == 0 || source_count != recipe[1] || meta.size() < ffmda_replay_meta_size()
    return 0
  if out_u.size() < source_count+2 || out_v.size() < source_count+2 || out_w.size() < source_count+2
    return 0
  z = ffmda_clear(meta,ffmda_replay_meta_size()) ## i64
  setup = i64[6]
  i = 0 ## i64
  while i < 6
    setup[i] = recipe[2+i]
    i += 1
  count = source_count + 2 ## i64
  work_u = i64[count]
  work_v = i64[count]
  work_w = i64[count]
  if ffmda_build_root(source_u,source_v,source_w,source_count,setup,work_u,work_v,work_w) != count
    return 0
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count) ## i64
  shape_u = recipe[38] ## i64
  shape_v = recipe[39] ## i64
  shape_w = recipe[40] ## i64
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,work_u,work_v,work_w,count,shape_u,shape_v,shape_w) != 1
    return 0
  meta[0] = 1
  step = 0 ## i64
  while step < recipe[8]
    if fftc_apply_code(work_u,work_v,work_w,count,recipe[9+step],0-1) != 1
      return 0
    z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
    if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,work_u,work_v,work_w,count,shape_u,shape_v,shape_w) != 1
      return 0
    meta[1] += 1
    step += 1
  if ffmda_preclose_equal(work_u,work_v,work_w,0,count,recipe) == 0
    return 0
  meta[2] = 1
  goals = i64[6]
  z = ffmda_recipe_goal(recipe,goals)
  if ffmda_goal_hit(work_u,work_v,work_w,0,count,goals) == 0
    return 0
  meta[3] = 1
  compacted = ffmh_compact(work_u,work_v,work_w,count,out_u,out_v,out_w) ## i64
  if compacted != source_count - 2 || compacted != recipe[35]
    return 0
  meta[4] = 1
  exact = ffrep_local_exact_shape(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted,shape_u,shape_v,shape_w) ## i64
  distance = ffmh_distance(source_u,source_v,source_w,source_count,out_u,out_v,out_w,compacted) ## i64
  if exact != 1 || distance < 1 || distance != recipe[36]
    return 0
  meta[5] = exact
  meta[6] = distance
  meta[7] = 1
  compacted

-> ffmda_replay_undo(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ffmda_recipe_valid(recipe) == 0 || source_count != recipe[1] || target_count != recipe[35] || target_count != source_count-2
    return 0
  if out_u.size() < source_count || out_v.size() < source_count || out_w.size() < source_count || meta.size() < ffmda_replay_meta_size()
    return 0
  z = ffmda_clear(meta,ffmda_replay_meta_size()) ## i64
  count = source_count + 2 ## i64
  work_u = i64[count]
  work_v = i64[count]
  work_w = i64[count]
  z = ffmh_copy(target_u,target_v,target_w,target_count,work_u,work_v,work_w) ## i64
  goals = i64[6]
  z = ffmda_recipe_goal(recipe,goals)
  slot = target_count ## i64
  copy = 0 ## i64
  while copy < 2
    work_u[slot] = goals[0]
    work_v[slot] = goals[1]
    work_w[slot] = goals[2]
    slot += 1
    copy += 1
  copy = 0
  while copy < 2
    work_u[slot] = goals[3]
    work_v[slot] = goals[4]
    work_w[slot] = goals[5]
    slot += 1
    copy += 1
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
  if ffmda_preclose_equal(work_u,work_v,work_w,0,count,recipe) == 0
    return 0
  meta[0] = 1
  shape_u = recipe[38] ## i64
  shape_v = recipe[39] ## i64
  shape_w = recipe[40] ## i64
  step = 0 ## i64
  while step < recipe[8]
    if fftc_apply_code(work_u,work_v,work_w,count,recipe[19+step],0-1) != 1
      return 0
    z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
    if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,work_u,work_v,work_w,count,shape_u,shape_v,shape_w) != 1
      return 0
    meta[1] += 1
    step += 1
  setup = i64[6]
  i = 0 ## i64
  while i < 6
    setup[i] = recipe[2+i]
    i += 1
  root_u = i64[count]
  root_v = i64[count]
  root_w = i64[count]
  if ffmda_build_root(source_u,source_v,source_w,source_count,setup,root_u,root_v,root_w) != count
    return 0
  z = ffrep_sort_slot(root_u,root_v,root_w,0,count)
  if ffrep_state_equal(work_u,work_v,work_w,0,root_u,root_v,root_w,0,count) == 0
    return 0
  meta[2] = 1
  # Explicitly undo both setup splits on the labelled (unsorted) construction.
  labeled_u = i64[count]
  labeled_v = i64[count]
  labeled_w = i64[count]
  if ffmda_build_root(source_u,source_v,source_w,source_count,setup,labeled_u,labeled_v,labeled_w) != count
    return 0
  merged = ffmh_merge_labeled(labeled_u,labeled_v,labeled_w,count,setup[3],source_count+1,setup[4]) ## i64
  if merged != source_count+1
    return 0
  merged = ffmh_merge_labeled(labeled_u,labeled_v,labeled_w,merged,setup[0],source_count,setup[1])
  if merged != source_count || fftc_terms_same_set(labeled_u,labeled_v,labeled_w,merged,source_u,source_v,source_w,source_count) != 1
    return 0
  meta[3] = 1
  exact = ffrep_local_exact_shape(target_u,target_v,target_w,target_count,labeled_u,labeled_v,labeled_w,merged,shape_u,shape_v,shape_w) ## i64
  if exact != 1
    return 0
  meta[4] = 1
  z = ffmh_copy(labeled_u,labeled_v,labeled_w,merged,out_u,out_v,out_w)
  meta[5] = exact
  meta[6] = ffmh_distance(target_u,target_v,target_w,target_count,out_u,out_v,out_w,merged)
  meta[7] = 1
  merged

# `prescribed` is one for the caller's concrete goals and zero to discover the
# first two-doublet goal.  A discovered winner is immediately converted into a
# concrete recipe and held to the same replay contract.  The workspace entry
# point lets campaign callers reuse the large BFS slabs across many windows.
-> ffmda_search_workspace(source_u, source_v, source_w, source_count, setup, goals, shape, limits, prescribed, states_u, states_v, states_w, parents, depths, hashes, table, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if source_count < 4 || source_count+2 > ffmda_max_count() || setup.size() < 6 || goals.size() < 6 || shape.size() < 3 || limits.size() < 3
    return 0
  if recipe.size() < ffmda_recipe_size() || stats.size() < ffmda_stats_size() || out_u.size() < source_count+2 || out_v.size() < source_count+2 || out_w.size() < source_count+2
    return 0
  min_depth = limits[0] ## i64
  max_depth = limits[1] ## i64
  node_cap = limits[2] ## i64
  if min_depth < 1 || max_depth < min_depth || max_depth > ffmda_max_depth() || node_cap < 16 || node_cap > 65536
    return 0
  if shape[0] < 1 || shape[1] < 1 || shape[2] < 1 || shape[0] > 63 || shape[1] > 63 || shape[2] > 63
    return 0
  if prescribed != 0 && ffmda_goal_distinct(goals) == 0
    return 0
  z = ffmda_clear(recipe,ffmda_recipe_size()) ## i64
  z = ffmda_clear(stats,ffmda_stats_size())
  stats[14] = prescribed
  if ffrep_terms_fit(source_u,source_v,source_w,source_count,shape[0],shape[1],shape[2]) == 0
    return 0
  stats[12] = 1
  count = source_count + 2 ## i64
  table_size = ffrep_table_size(node_cap) ## i64
  if states_u.size() < node_cap*count || states_v.size() < node_cap*count || states_w.size() < node_cap*count
    return 0
  if parents.size() < node_cap || depths.size() < node_cap || hashes.size() < node_cap || table.size() < table_size
    return 0
  root_u = i64[count]
  root_v = i64[count]
  root_w = i64[count]
  if ffmda_build_root(source_u,source_v,source_w,source_count,setup,root_u,root_v,root_w) != count
    return 0
  z = ffrep_sort_slot(root_u,root_v,root_w,0,count)
  root_goals = i64[6]
  root_hit = 0 ## i64
  if prescribed != 0
    root_hit = ffmda_goal_hit(root_u,root_v,root_w,0,count,goals)
  if prescribed == 0
    root_hit = ffmda_find_goals(root_u,root_v,root_w,0,count,root_goals)
  stats[17] = root_hit

  tree_meta = i64[6]
  nodes = ffrep_build_tree(root_u,root_v,root_w,count,max_depth,node_cap,states_u,states_v,states_w,parents,depths,hashes,table,tree_meta) ## i64
  if nodes < 1
    return 0
  stats[0] = nodes
  stats[1] = tree_meta[1]
  stats[2] = tree_meta[2]
  stats[3] = tree_meta[3]
  stats[4] = tree_meta[4]
  stats[13] = tree_meta[5]
  compact_u = i64[count]
  compact_v = i64[count]
  compact_w = i64[count]
  candidate_u = i64[count]
  candidate_v = i64[count]
  candidate_w = i64[count]
  best_node = 0 - 1 ## i64
  best_depth = max_depth + 1 ## i64
  best_distance = 0 ## i64
  best_density = 1 << 30 ## i64
  best_goals = i64[6]
  candidate_goals = i64[6]
  if prescribed != 0
    i = 0 ## i64
    while i < 6
      candidate_goals[i] = goals[i]
      i += 1
  node = 1 ## i64
  while node < nodes
    depth = depths[node] ## i64
    if depth >= min_depth && depth <= max_depth
      stats[5] += 1
      hit = 0 ## i64
      if prescribed != 0
        hit = ffmda_goal_hit(states_u,states_v,states_w,node*count,count,candidate_goals)
      if prescribed == 0
        hit = ffmda_find_goals(states_u,states_v,states_w,node*count,count,candidate_goals)
      if hit != 0
        stats[6] += 1
        z = ffrep_copy_slot(states_u,states_v,states_w,node*count,count,candidate_u,candidate_v,candidate_w,0)
        compacted = ffmh_compact(candidate_u,candidate_v,candidate_w,count,compact_u,compact_v,compact_w) ## i64
        if compacted == source_count-2
          exact = ffrep_local_exact_shape(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted,shape[0],shape[1],shape[2]) ## i64
          distance = ffmh_distance(source_u,source_v,source_w,source_count,compact_u,compact_v,compact_w,compacted) ## i64
          if exact == 1 && distance > 0
            stats[7] += 1
            density = fftc_density(compact_u,compact_v,compact_w,compacted) - fftc_density(source_u,source_v,source_w,source_count) ## i64
            better = 0 ## i64
            if best_node < 0 || depth < best_depth
              better = 1
            if depth == best_depth && distance > best_distance
              better = 1
            if depth == best_depth && distance == best_distance && density < best_density
              better = 1
            if better != 0
              best_node = node
              best_depth = depth
              best_distance = distance
              best_density = density
              i = 0
              while i < 6
                best_goals[i] = candidate_goals[i]
                i += 1
    node += 1
  if best_node < 0
    return 0

  recipe[0] = 1
  recipe[1] = source_count
  i = 0
  while i < 6
    recipe[2+i] = setup[i]
    recipe[29+i] = best_goals[i]
    i += 1
  recipe[8] = best_depth
  recipe[35] = source_count - 2
  recipe[36] = best_distance
  recipe[37] = best_density
  recipe[38] = shape[0]
  recipe[39] = shape[1]
  recipe[40] = shape[2]
  recipe[41] = 1
  if ffmda_compile_path(states_u,states_v,states_w,parents,count,best_node,best_depth,recipe) == 0
    recipe[41] = 0
    return 0
  z = ffmda_store_preclose(states_u,states_v,states_w,best_node*count,count,recipe)
  replay_meta = i64[ffmda_replay_meta_size()]
  result = ffmda_replay_forward(source_u,source_v,source_w,source_count,recipe,out_u,out_v,out_w,replay_meta) ## i64
  if result != source_count-2 || replay_meta[7] != 1
    recipe[41] = 0
    return 0
  stats[10] = 1
  undo_u = i64[source_count]
  undo_v = i64[source_count]
  undo_w = i64[source_count]
  undo_meta = i64[ffmda_replay_meta_size()]
  undone = ffmda_replay_undo(source_u,source_v,source_w,source_count,out_u,out_v,out_w,result,recipe,undo_u,undo_v,undo_w,undo_meta) ## i64
  if undone != source_count || undo_meta[7] != 1 || fftc_terms_same_set(source_u,source_v,source_w,source_count,undo_u,undo_v,undo_w,undone) != 1
    recipe[41] = 0
    return 0
  stats[8] = best_depth
  stats[9] = result
  stats[11] = 1
  stats[15] = best_distance
  stats[16] = best_density
  stats[18] = best_node
  stats[19] = 1
  result

# Convenience wrapper for one-shot controls.  Campaigns should use
# `ffmda_search_workspace` so repeated windows do not retain one large slab per
# call in runtimes without prompt collection of dead typed arrays.
-> ffmda_search(source_u, source_v, source_w, source_count, setup, goals, shape, limits, prescribed, out_u, out_v, out_w, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if limits.size() < 3 || source_count < 1
    return 0
  count = source_count + 2 ## i64
  node_cap = limits[2] ## i64
  if node_cap < 1 || node_cap > 65536 || count < 6 || count > ffmda_max_count()
    return 0
  table_size = ffrep_table_size(node_cap) ## i64
  states_u = i64[node_cap*count]
  states_v = i64[node_cap*count]
  states_w = i64[node_cap*count]
  parents = i64[node_cap]
  depths = i64[node_cap]
  hashes = i64[node_cap]
  table = i64[table_size]
  ffmda_search_workspace(source_u,source_v,source_w,source_count,setup,goals,shape,limits,prescribed,states_u,states_v,states_w,parents,depths,hashes,table,out_u,out_v,out_w,recipe,stats)
