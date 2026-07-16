# Endpoint-to-word compiler for a prescribed two-rank rectangular reduction.
#
# A k-to-(k-2) local replacement is lifted back to k terms by splitting two
# distinct target terms.  The bounded same-rank endpoint compiler resolves the
# state-dependent middle word, then the two named split pairs are merged.  In
# Rubik language, the target fixes the cleanup and the search compiles only the
# setup/trigger needed to reach it.
#
# Recipe (36 words): the 28-word `rect_endpoint_path` recipe followed by
#   28 wrapper version (=2),
#   29..31 first target index / split axis / split part,
#   32..34 second target index / split axis / split part,
#   35 cleanup order (0 first-then-second, 1 second-then-first).
# Search stats (24 words): the 16 base stats followed by
#   16 lifted local exact, 17 forward replay, 18 undo replay, 19 success,
#   20 first cleanup legal, 21 second cleanup legal,
#   22 intermediate exact, 23 final exact.
# Replay meta (16 words): the eight base replay words followed by
#   8 first cleanup/reverse split legal, 9 first prefix exact,
#   10 second cleanup/reverse split legal, 11 final target/lift set match,
#   12 final local exact, 13 success, 14 cleanup order, 15 reserved.
#
# This module is deliberately offline.  It compiles and verifies a supplied
# endpoint; it does not put speculative rank-debt words into the live fleet.

use rect_endpoint_path
use macro_holonomy

-> fferd2_recipe_size() i64
  36

-> fferd2_stats_size() i64
  24

-> fferd2_meta_size() i64
  16

-> fferd2_auto_stats_size() i64
  32

-> fferd2_descriptor_cap() i64
  # At the nine-term local ceiling there are at most 7*3*9 fallback
  # descriptors and C(9,2)*3 concrete source-pair descriptors.
  384

-> fferd2_copy_prefix(source, dest, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest[i] = source[i]
    i += 1
  count

-> fferd2_recipe_valid(recipe, source_count, target_count) (i64[] i64 i64) i64
  if recipe.size() < fferd2_recipe_size() || recipe[28] != 2
    return 0
  if source_count < 3 || source_count > ffrep_max_count() || target_count != source_count - 2
    return 0
  if recipe[2] != source_count || recipe[3] != source_count
    return 0
  if recipe[29] < 0 || recipe[29] >= target_count || recipe[32] < 0 || recipe[32] >= target_count || recipe[29] == recipe[32]
    return 0
  if recipe[30] < 0 || recipe[30] > 2 || recipe[33] < 0 || recipe[33] > 2 || recipe[31] <= 0 || recipe[34] <= 0
    return 0
  if recipe[35] < 0 || recipe[35] > 1
    return 0
  ffrep_recipe_valid(recipe)

-> fferd2_split_children(target_u, target_v, target_w, target_index, axis, part, child_u, child_v, child_w) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  if target_index < 0 || target_index >= target_u.size() || child_u.size() < 2 || child_v.size() < 2 || child_w.size() < 2
    return 0
  child_u[0] = target_u[target_index]
  child_v[0] = target_v[target_index]
  child_w[0] = target_w[target_index]
  child_u[1] = target_u[target_index]
  child_v[1] = target_v[target_index]
  child_w[1] = target_w[target_index]
  factor = ffmh_axis_get(target_u,target_v,target_w,target_index,axis) ## i64
  other = factor ^ part ## i64
  if factor == 0 || part == factor || other == 0
    return 0
  z = ffmh_axis_set(child_u,child_v,child_w,0,axis,part) ## i64
  z = ffmh_axis_set(child_u,child_v,child_w,1,axis,other)
  2

-> fferd2_build_lift(target_u, target_v, target_w, target_count, recipe, lift_u, lift_v, lift_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  source_count = target_count + 2 ## i64
  if target_count < 2 || source_count > ffrep_max_count() || target_u.size() < target_count || target_v.size() < target_count || target_w.size() < target_count
    return 0
  if lift_u.size() < source_count || lift_v.size() < source_count || lift_w.size() < source_count
    return 0
  z = ffrep_copy_slot(target_u,target_v,target_w,0,target_count,lift_u,lift_v,lift_w,0) ## i64
  count = ffmh_split_labeled(lift_u,lift_v,lift_w,target_count,source_count,recipe[29],recipe[30],recipe[31]) ## i64
  if count != target_count + 1
    return 0
  count = ffmh_split_labeled(lift_u,lift_v,lift_w,count,source_count,recipe[32],recipe[33],recipe[34])
  if count != source_count
    return 0
  z = ffrep_sort_slot(lift_u,lift_v,lift_w,0,source_count)
  source_count

-> fferd2_find_term(us, vs, ws, count, u, v, w, skip) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if i != skip && us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

-> fferd2_merge_named(work_u, work_v, work_w, count, child_u, child_v, child_w, axis) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  first = fferd2_find_term(work_u,work_v,work_w,count,child_u[0],child_v[0],child_w[0],0-1) ## i64
  second = fferd2_find_term(work_u,work_v,work_w,count,child_u[1],child_v[1],child_w[1],first) ## i64
  if first < 0 || second < 0
    return 0
  ffmh_merge_labeled(work_u,work_v,work_w,count,first,second,axis)

-> fferd2_replay_forward(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if fferd2_recipe_valid(recipe,source_count,target_count) == 0 || out_u.size() < target_count || out_v.size() < target_count || out_w.size() < target_count || meta.size() < fferd2_meta_size()
    return 0
  z = ffrep_clear(meta,fferd2_meta_size()) ## i64
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd2_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
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
  z = fferd2_copy_prefix(base_meta,meta,ffrep_replay_meta_size())

  child0_u = i64[2]
  child0_v = i64[2]
  child0_w = i64[2]
  child1_u = i64[2]
  child1_v = i64[2]
  child1_w = i64[2]
  if fferd2_split_children(target_u,target_v,target_w,recipe[29],recipe[30],recipe[31],child0_u,child0_v,child0_w) != 2
    return 0
  if fferd2_split_children(target_u,target_v,target_w,recipe[32],recipe[33],recipe[34],child1_u,child1_v,child1_w) != 2
    return 0

  first_u = child0_u
  first_v = child0_v
  first_w = child0_w
  second_u = child1_u
  second_v = child1_v
  second_w = child1_w
  first_axis = recipe[30] ## i64
  second_axis = recipe[33] ## i64
  if recipe[35] == 1
    first_u = child1_u
    first_v = child1_v
    first_w = child1_w
    second_u = child0_u
    second_v = child0_v
    second_w = child0_w
    first_axis = recipe[33]
    second_axis = recipe[30]
  meta[14] = recipe[35]
  count = fferd2_merge_named(work_u,work_v,work_w,source_count,first_u,first_v,first_w,first_axis) ## i64
  if count != source_count - 1
    return 0
  meta[8] = 1
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,work_u,work_v,work_w,count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[9] = 1
  count = fferd2_merge_named(work_u,work_v,work_w,count,second_u,second_v,second_w,second_axis)
  if count != target_count
    return 0
  meta[10] = 1
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
  if fftc_terms_same_set(work_u,work_v,work_w,count,target_u,target_v,target_w,target_count) != 1
    return 0
  meta[11] = 1
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,work_u,work_v,work_w,count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[12] = 1
  z = ffrep_copy_slot(work_u,work_v,work_w,0,count,out_u,out_v,out_w,0)
  meta[13] = 1
  count

-> fferd2_replay_undo(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if fferd2_recipe_valid(recipe,source_count,target_count) == 0 || out_u.size() < source_count || out_v.size() < source_count || out_w.size() < source_count || meta.size() < fferd2_meta_size()
    return 0
  z = ffrep_clear(meta,fferd2_meta_size()) ## i64
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd2_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
    return 0

  # Replay the inverse cleanup instead of trusting the constructed lift as an
  # implicit jump.  Cleanup merges must be undone in reverse order; both split
  # prefixes cross an independent exhaustive local tensor gate.
  reverse_u = i64[source_count]
  reverse_v = i64[source_count]
  reverse_w = i64[source_count]
  z = ffrep_copy_slot(target_u,target_v,target_w,0,target_count,reverse_u,reverse_v,reverse_w,0)
  first_target = recipe[32] ## i64
  first_axis = recipe[33] ## i64
  first_part = recipe[34] ## i64
  second_target = recipe[29] ## i64
  second_axis = recipe[30] ## i64
  second_part = recipe[31] ## i64
  if recipe[35] == 1
    first_target = recipe[29]
    first_axis = recipe[30]
    first_part = recipe[31]
    second_target = recipe[32]
    second_axis = recipe[33]
    second_part = recipe[34]
  meta[14] = recipe[35]
  reverse_count = ffmh_split_labeled(reverse_u,reverse_v,reverse_w,target_count,source_count,first_target,first_axis,first_part) ## i64
  if reverse_count != target_count + 1
    return 0
  meta[8] = 1
  if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,reverse_u,reverse_v,reverse_w,reverse_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[9] = 1
  reverse_count = ffmh_split_labeled(reverse_u,reverse_v,reverse_w,reverse_count,source_count,second_target,second_axis,second_part)
  if reverse_count != source_count
    return 0
  meta[10] = 1
  z = ffrep_sort_slot(reverse_u,reverse_v,reverse_w,0,source_count)
  if fftc_terms_same_set(reverse_u,reverse_v,reverse_w,source_count,lift_u,lift_v,lift_w,source_count) != 1
    return 0
  meta[11] = 1
  if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,reverse_u,reverse_v,reverse_w,source_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[12] = 1

  base_meta = i64[ffrep_replay_meta_size()]
  undone = ffrep_replay_undo(source_u,source_v,source_w,source_count,reverse_u,reverse_v,reverse_w,source_count,recipe,out_u,out_v,out_w,base_meta) ## i64
  if undone != source_count
    return 0
  z = fferd2_copy_prefix(base_meta,meta,ffrep_replay_meta_size())
  if fftc_terms_same_set(out_u,out_v,out_w,source_count,source_u,source_v,source_w,source_count) != 1
    return 0
  if ffrep_local_exact_shape(target_u,target_v,target_w,target_count,out_u,out_v,out_w,source_count,recipe[5],recipe[6],recipe[7]) != 1
    return 0
  meta[13] = 1
  source_count

-> fferd2_search(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, udim, vdim, wdim, split_target0, split_axis0, split_part0, split_target1, split_axis1, split_part1, cleanup_order, max_depth, node_cap, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if source_count < 3 || source_count > ffrep_max_count() || target_count != source_count - 2 || target_count < 2
    return 0
  if recipe.size() < fferd2_recipe_size() || stats.size() < fferd2_stats_size()
    return 0
  if split_target0 < 0 || split_target0 >= target_count || split_target1 < 0 || split_target1 >= target_count || split_target0 == split_target1
    return 0
  if split_axis0 < 0 || split_axis0 > 2 || split_axis1 < 0 || split_axis1 > 2 || split_part0 <= 0 || split_part1 <= 0 || cleanup_order < 0 || cleanup_order > 1
    return 0
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  z = ffrep_fill(recipe,fferd2_recipe_size(),0-1) ## i64
  z = ffrep_clear(stats,fferd2_stats_size())
  recipe[0] = 1
  recipe[1] = 0
  recipe[2] = source_count
  recipe[3] = source_count
  recipe[4] = 0
  recipe[5] = udim
  recipe[6] = vdim
  recipe[7] = wdim
  recipe[28] = 2
  recipe[29] = split_target0
  recipe[30] = split_axis0
  recipe[31] = split_part0
  recipe[32] = split_target1
  recipe[33] = split_axis1
  recipe[34] = split_part1
  recipe[35] = cleanup_order
  lift_u = i64[source_count]
  lift_v = i64[source_count]
  lift_w = i64[source_count]
  if fferd2_build_lift(target_u,target_v,target_w,target_count,recipe,lift_u,lift_v,lift_w) != source_count
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
    z = fferd2_copy_prefix(base_recipe,recipe,ffrep_recipe_size())
    z = fferd2_copy_prefix(base_stats,stats,ffrep_stats_size())
    recipe[28] = 2
    recipe[29] = split_target0
    recipe[30] = split_axis0
    recipe[31] = split_part0
    recipe[32] = split_target1
    recipe[33] = split_axis1
    recipe[34] = split_part1
    recipe[35] = cleanup_order
    stats[16] = 1
  replay_u = i64[target_count]
  replay_v = i64[target_count]
  replay_w = i64[target_count]
  replay_meta = i64[fferd2_meta_size()]
  if fferd2_replay_forward(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,replay_u,replay_v,replay_w,replay_meta) != target_count || replay_meta[13] != 1
    return 0
  stats[17] = 1
  stats[20] = replay_meta[8]
  stats[21] = replay_meta[10]
  stats[22] = replay_meta[9]
  stats[23] = replay_meta[12]
  undo_u = i64[source_count]
  undo_v = i64[source_count]
  undo_w = i64[source_count]
  if fferd2_replay_undo(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,undo_u,undo_v,undo_w,replay_meta) != source_count || replay_meta[13] != 1
    return 0
  stats[18] = 1
  stats[19] = 1
  recipe[4] + 2

# Add one canonical cleanup descriptor. `kind` is zero for a factor-mask
# fallback and one for a concrete source-pair merge.  Equivalent descriptors
# are deduplicated independent of their provenance.
-> fferd2_add_descriptor(targets, axes, parts, kinds, count, target, axis, part, kind, target_u, target_v, target_w, udim, vdim, wdim) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64 i64 i64) i64
  if count < 0 || count >= targets.size() || axes.size() <= count || parts.size() <= count || kinds.size() <= count
    return count
  if target < 0 || target >= target_u.size() || target >= target_v.size() || target >= target_w.size() || axis < 0 || axis > 2
    return count
  width = udim ## i64
  if axis == 1
    width = vdim
  if axis == 2
    width = wdim
  factor = ffmh_axis_get(target_u,target_v,target_w,target,axis) ## i64
  if part == factor || (factor ^ part) == 0 || ffrep_factor_fits(part,width) == 0
    return count
  i = 0 ## i64
  while i < count
    if targets[i] == target && axes[i] == axis && parts[i] == part
      if kind > kinds[i]
        kinds[i] = kind
      return count
    i += 1
  targets[count] = target
  axes[count] = axis
  parts[count] = part
  kinds[count] = kind
  count + 1

# Automatically enumerate a bounded pair of cleanup scaffolds.  Observed
# source factor masks provide broad proposals; concrete mergeable source pairs
# annotate the subset already visible at the endpoint.  Distinct target terms
# are paired once, both cleanup orders are tried, and every candidate crosses
# the full `fferd2_search` forward/undo audit before it can win.
#
# Auto stats extend the selected 24-word search stats with:
#   24 scaffold pairs tried, 25 successful compiles, 26 descriptors,
#   27 concrete source-pair descriptors, 28 fallback descriptors,
#   29 order-zero trials, 30 order-one trials, 31 candidate cap reached.
-> fferd2_search_auto(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, udim, vdim, wdim, max_depth, node_cap, candidate_cap, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if source_count < 3 || source_count > ffrep_max_count() || target_count != source_count - 2 || target_count < 2
    return 0
  if recipe.size() < fferd2_recipe_size() || stats.size() < fferd2_auto_stats_size() || candidate_cap < 1 || candidate_cap > 4096
    return 0
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  z = ffrep_fill(recipe,fferd2_recipe_size(),0-1) ## i64
  z = ffrep_clear(stats,fferd2_auto_stats_size()) ## i64
  targets = i64[fferd2_descriptor_cap()]
  axes = i64[fferd2_descriptor_cap()]
  parts = i64[fferd2_descriptor_cap()]
  kinds = i64[fferd2_descriptor_cap()]
  descriptor_count = 0 ## i64

  # Target-major ordering makes pairs for different target terms appear early
  # while retaining deterministic source-mask proposal order.
  target = 0 ## i64
  while target < target_count
    axis = 0 ## i64
    while axis < 3
      source = 0 ## i64
      while source < source_count
        part = ffmh_axis_get(source_u,source_v,source_w,source,axis) ## i64
        descriptor_count = fferd2_add_descriptor(targets,axes,parts,kinds,descriptor_count,target,axis,part,0,target_u,target_v,target_w,udim,vdim,wdim)
        source += 1
      axis += 1
    target += 1

  first = 0 ## i64
  while first < source_count-1
    second = first + 1 ## i64
    while second < source_count
      axis = 0
      while axis < 3
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
          if axis == 0
            merged_u = merged_factor
          if axis == 1
            merged_v = merged_factor
          if axis == 2
            merged_w = merged_factor
          if merged_factor != 0
            target = 0
            while target < target_count
              if target_u[target] == merged_u && target_v[target] == merged_v && target_w[target] == merged_w
                descriptor_count = fferd2_add_descriptor(targets,axes,parts,kinds,descriptor_count,target,axis,part,1,target_u,target_v,target_w,udim,vdim,wdim)
              target += 1
        axis += 1
      second += 1
    first += 1

  fallback_descriptors = 0 ## i64
  pair_descriptors = 0 ## i64
  i = 0 ## i64
  while i < descriptor_count
    if kinds[i] == 1
      pair_descriptors += 1
    else
      fallback_descriptors += 1
    i += 1

  best = 0 ## i64
  tried = 0 ## i64
  hits = 0 ## i64
  order0 = 0 ## i64
  order1 = 0 ## i64
  stop = 0 ## i64
  candidate_total = 0 ## i64
  left = 0 ## i64
  while left < descriptor_count-1
    right = left + 1 ## i64
    while right < descriptor_count
      if targets[left] != targets[right]
        candidate_total += 2
      right += 1
    left += 1
  trial_recipe = i64[fferd2_recipe_size()]
  trial_stats = i64[fferd2_stats_size()]
  left = 0
  while left < descriptor_count-1 && tried < candidate_cap && stop == 0
    right = left + 1 ## i64
    while right < descriptor_count && tried < candidate_cap && stop == 0
      if targets[left] != targets[right]
        order = 0 ## i64
        while order < 2 && tried < candidate_cap && stop == 0
          tried += 1
          if order == 0
            order0 += 1
          else
            order1 += 1
          found = fferd2_search(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim,targets[left],axes[left],parts[left],targets[right],axes[right],parts[right],order,max_depth,node_cap,trial_recipe,trial_stats) ## i64
          if found > 0
            hits += 1
            if best == 0 || found < best
              best = found
              z = fferd2_copy_prefix(trial_recipe,recipe,fferd2_recipe_size())
              z = fferd2_copy_prefix(trial_stats,stats,fferd2_stats_size())
            if best == 2
              stop = 1
          order += 1
      right += 1
    left += 1
  stats[24] = tried
  stats[25] = hits
  stats[26] = descriptor_count
  stats[27] = pair_descriptors
  stats[28] = fallback_descriptors
  stats[29] = order0
  stats[30] = order1
  if tried >= candidate_cap && tried < candidate_total && stop == 0
    stats[31] = 1
  best
