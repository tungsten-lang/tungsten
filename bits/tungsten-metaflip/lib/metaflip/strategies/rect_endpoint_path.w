# Deterministic endpoint-to-word compiler for small rectangular fringes.
#
# The caller supplies two exact local term multisets of the same cardinality.
# A bounded bidirectional BFS searches the graph of legal ordered pair flips,
# canonicalizing the multiset after every edge.  Every edge is an exact GF(2)
# identity.  The returned recipe contains separately resolved forward and undo
# words, so replay never assumes that a syntactic setup remains legal after a
# trigger.
#
# This is deliberately offline.  It performs no scheduling or file I/O and
# has a hard nine-term, depth-ten, caller-supplied node envelope. Nine labels
# cover a lifted 7 -> 6 replacement from the rectangular k-XOR scout.
#
# Recipe (28 words):
#   0 version, 1 mode (zero is same-rank), 2 source count, 3 target count,
#   4 path length, 5..7 U/V/W bit widths,
#   8..17 forward codes, 18..27 undo codes.
#
# Search stats (16 words):
#   0 forward states, 1 backward states,
#   2 forward codes examined, 3 backward codes examined,
#   4 legal edges, 5 revisits, 6 meets, 7 path length,
#   8 forward meet depth, 9 backward meet depth, 10 cap reached,
#   11 forward replay exact, 12 undo replay exact, 13 input local exact,
#   14 table capacity, 15 success.
#
# Replay meta (8 words):
#   0 legal steps, 1 exact prefixes, 2 final term-set match,
#   3 final local exact, 4 input local exact, remaining reserved.

use tunnel

-> ffrep_max_count() i64
  9

-> ffrep_max_depth() i64
  10

-> ffrep_recipe_size() i64
  28

-> ffrep_stats_size() i64
  16

-> ffrep_replay_meta_size() i64
  8

-> ffrep_clear(values, count) (i64[] i64) i64
  i = 0 ## i64
  while i < count
    values[i] = 0
    i += 1
  count

-> ffrep_fill(values, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    values[i] = value
    i += 1
  count

-> ffrep_copy_slot(source_u, source_v, source_w, source_offset, count, dest_u, dest_v, dest_w, dest_offset) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    dest_u[dest_offset+i] = source_u[source_offset+i]
    dest_v[dest_offset+i] = source_v[source_offset+i]
    dest_w[dest_offset+i] = source_w[source_offset+i]
    i += 1
  count

-> ffrep_term_before(u0, v0, w0, u1, v1, w1) (i64 i64 i64 i64 i64 i64) i64
  if u0 < u1
    return 1
  if u0 > u1
    return 0
  if v0 < v1
    return 1
  if v0 > v1
    return 0
  if w0 < w1
    return 1
  0

-> ffrep_sort_slot(us, vs, ws, offset, count) (i64[] i64[] i64[] i64 i64) i64
  i = 1 ## i64
  while i < count
    u = us[offset+i] ## i64
    v = vs[offset+i] ## i64
    w = ws[offset+i] ## i64
    j = i ## i64
    while j > 0 && ffrep_term_before(u,v,w,us[offset+j-1],vs[offset+j-1],ws[offset+j-1]) == 1
      us[offset+j] = us[offset+j-1]
      vs[offset+j] = vs[offset+j-1]
      ws[offset+j] = ws[offset+j-1]
      j -= 1
    us[offset+j] = u
    vs[offset+j] = v
    ws[offset+j] = w
    i += 1
  count

-> ffrep_state_equal(left_u, left_v, left_w, left_offset, right_u, right_v, right_w, right_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if left_u[left_offset+i] != right_u[right_offset+i] || left_v[left_offset+i] != right_v[right_offset+i] || left_w[left_offset+i] != right_w[right_offset+i]
      return 0
    i += 1
  1

-> ffrep_factor_fits(value, width) (i64 i64) i64
  if value <= 0 || width < 1 || width > 63
    return 0
  if width < 63 && (value >> width) != 0
    return 0
  1

-> ffrep_terms_fit(us, vs, ws, count, udim, vdim, wdim) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  if count < 1 || us.size() < count || vs.size() < count || ws.size() < count
    return 0
  i = 0 ## i64
  while i < count
    if ffrep_factor_fits(us[i],udim) == 0 || ffrep_factor_fits(vs[i],vdim) == 0 || ffrep_factor_fits(ws[i],wdim) == 0
      return 0
    i += 1
  1

# Exhaustive unequal-width local tensor comparison.  This is independent of
# the flip identity and is used on the inputs plus every replay prefix.
-> ffrep_local_exact_shape(left_u, left_v, left_w, left_count, right_u, right_v, right_w, right_count, udim, vdim, wdim) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  if ffrep_terms_fit(left_u,left_v,left_w,left_count,udim,vdim,wdim) == 0
    return 0
  if ffrep_terms_fit(right_u,right_v,right_w,right_count,udim,vdim,wdim) == 0
    return 0
  ai = 0 ## i64
  while ai < udim
    bi = 0 ## i64
    while bi < vdim
      ci = 0 ## i64
      while ci < wdim
        parity = 0 ## i64
        term = 0 ## i64
        while term < left_count
          if ((left_u[term] >> ai) & 1) != 0 && ((left_v[term] >> bi) & 1) != 0 && ((left_w[term] >> ci) & 1) != 0
            parity = parity ^ 1
          term += 1
        term = 0
        while term < right_count
          if ((right_u[term] >> ai) & 1) != 0 && ((right_v[term] >> bi) & 1) != 0 && ((right_w[term] >> ci) & 1) != 0
            parity = parity ^ 1
          term += 1
        if parity != 0
          return 0
        ci += 1
      bi += 1
    ai += 1
  1

-> ffrep_state_hash(us, vs, ws, offset, count) (i64[] i64[] i64[] i64 i64) i64
  h = (count * 3202034522624059733) & 9223372036854775807 ## i64
  i = 0 ## i64
  while i < count
    label = i + 1 ## i64
    term = ffw_term_zobrist(us[offset+i] ^ label,vs[offset+i] ^ (label << 9),ws[offset+i] ^ (label << 18)) ## i64
    h = ((h ^ term) * 2862933555777941757) & 9223372036854775807
    h = h ^ (h >> 31)
    i += 1
  h & 9223372036854775807

-> ffrep_table_size(node_cap) (i64) i64
  size = 16 ## i64
  while size < node_cap * 4
    size *= 2
  size

-> ffrep_table_find(table, mask, hashes, states_u, states_v, states_w, count, query_u, query_v, query_w, query_offset, query_hash) (i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  slot = query_hash & mask ## i64
  probes = 0 ## i64
  while probes <= mask
    entry = table[slot] ## i64
    if entry == 0
      return 0 - 1
    index = entry - 1 ## i64
    if hashes[index] == query_hash
      if ffrep_state_equal(states_u,states_v,states_w,index*count,query_u,query_v,query_w,query_offset,count) == 1
        return index
    slot = (slot + 1) & mask
    probes += 1
  0 - 1

-> ffrep_table_insert(table, mask, hash, index) (i64[] i64 i64 i64) i64
  slot = hash & mask ## i64
  probes = 0 ## i64
  while probes <= mask
    if table[slot] == 0
      table[slot] = index + 1
      return 1
    slot = (slot + 1) & mask
    probes += 1
  0

# Build one complete BFS tree through depth_limit unless a new unique state
# would exceed node_cap.  meta: nodes, codes, legal, revisits, capped, depth.
-> ffrep_build_tree(root_u, root_v, root_w, count, depth_limit, node_cap, states_u, states_v, states_w, parents, depths, hashes, table, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if count < 2 || count > ffrep_max_count() || depth_limit < 0 || depth_limit > ffrep_max_depth() || node_cap < 1
    return 0
  if states_u.size() < node_cap*count || states_v.size() < node_cap*count || states_w.size() < node_cap*count
    return 0
  if parents.size() < node_cap || depths.size() < node_cap || hashes.size() < node_cap || meta.size() < 6
    return 0
  z = ffrep_clear(table,table.size()) ## i64
  z = ffrep_clear(meta,6)
  z = ffrep_copy_slot(root_u,root_v,root_w,0,count,states_u,states_v,states_w,0)
  z = ffrep_sort_slot(states_u,states_v,states_w,0,count)
  parents[0] = 0 - 1
  depths[0] = 0
  hashes[0] = ffrep_state_hash(states_u,states_v,states_w,0,count)
  if ffrep_table_insert(table,table.size()-1,hashes[0],0) == 0
    return 0
  nodes = 1 ## i64
  cursor = 0 ## i64
  stop = 0 ## i64
  code_count = fftc_code_count(count) ## i64
  child_u = i64[count]
  child_v = i64[count]
  child_w = i64[count]
  while cursor < nodes && stop == 0
    depth = depths[cursor] ## i64
    if depth > meta[5]
      meta[5] = depth
    if depth < depth_limit
      code = 0 ## i64
      while code < code_count && stop == 0
        meta[1] += 1
        z = ffrep_copy_slot(states_u,states_v,states_w,cursor*count,count,child_u,child_v,child_w,0)
        if fftc_apply_code(child_u,child_v,child_w,count,code,0-1) == 1
          meta[2] += 1
          z = ffrep_sort_slot(child_u,child_v,child_w,0,count)
          hash = ffrep_state_hash(child_u,child_v,child_w,0,count) ## i64
          seen = ffrep_table_find(table,table.size()-1,hashes,states_u,states_v,states_w,count,child_u,child_v,child_w,0,hash) ## i64
          if seen >= 0
            meta[3] += 1
          else
            if nodes >= node_cap
              meta[4] = 1
              stop = 1
            else
              z = ffrep_copy_slot(child_u,child_v,child_w,0,count,states_u,states_v,states_w,nodes*count)
              parents[nodes] = cursor
              depths[nodes] = depth + 1
              hashes[nodes] = hash
              if ffrep_table_insert(table,table.size()-1,hash,nodes) == 0
                return 0
              nodes += 1
        code += 1
    cursor += 1
  meta[0] = nodes
  nodes

# Resolve one canonical adjacency.  Searching again avoids depending on label
# positions that changed during canonical sorting.
-> ffrep_find_transition(source_u, source_v, source_w, source_offset, target_u, target_v, target_w, target_offset, count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64) i64
  scratch_u = i64[count]
  scratch_v = i64[count]
  scratch_w = i64[count]
  code = 0 ## i64
  code_count = fftc_code_count(count) ## i64
  while code < code_count
    z = ffrep_copy_slot(source_u,source_v,source_w,source_offset,count,scratch_u,scratch_v,scratch_w,0) ## i64
    if fftc_apply_code(scratch_u,scratch_v,scratch_w,count,code,0-1) == 1
      z = ffrep_sort_slot(scratch_u,scratch_v,scratch_w,0,count)
      if ffrep_state_equal(scratch_u,scratch_v,scratch_w,0,target_u,target_v,target_w,target_offset,count) == 1
        return code
    code += 1
  0 - 1

-> ffrep_recipe_valid(recipe) (i64[]) i64
  if recipe.size() < ffrep_recipe_size() || recipe[0] != 1 || recipe[1] != 0
    return 0
  if recipe[2] < 2 || recipe[2] > ffrep_max_count() || recipe[3] != recipe[2]
    return 0
  # A zero-edge path is useful when a rank-down endpoint is already the
  # requested lifted target and only its final merge remains.  Same-rank
  # searches still reject identical endpoints; replay merely supports the
  # explicit identity word used by the rank-down wrapper.
  if recipe[4] < 0 || recipe[4] > ffrep_max_depth()
    return 0
  if recipe[5] < 1 || recipe[5] > 63 || recipe[6] < 1 || recipe[6] > 63 || recipe[7] < 1 || recipe[7] > 63
    return 0
  1

-> ffrep_replay_forward(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ffrep_recipe_valid(recipe) == 0 || source_count != recipe[2] || target_count != recipe[3]
    return 0
  count = source_count ## i64
  if source_u.size() < count || source_v.size() < count || source_w.size() < count || target_u.size() < count || target_v.size() < count || target_w.size() < count
    return 0
  if out_u.size() < count || out_v.size() < count || out_w.size() < count || meta.size() < ffrep_replay_meta_size()
    return 0
  z = ffrep_clear(meta,ffrep_replay_meta_size()) ## i64
  udim = recipe[5] ## i64
  vdim = recipe[6] ## i64
  wdim = recipe[7] ## i64
  if ffrep_local_exact_shape(source_u,source_v,source_w,count,target_u,target_v,target_w,count,udim,vdim,wdim) != 1
    return 0
  meta[4] = 1
  work_u = i64[count]
  work_v = i64[count]
  work_w = i64[count]
  target_cu = i64[count]
  target_cv = i64[count]
  target_cw = i64[count]
  z = ffrep_copy_slot(source_u,source_v,source_w,0,count,work_u,work_v,work_w,0)
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
  z = ffrep_copy_slot(target_u,target_v,target_w,0,count,target_cu,target_cv,target_cw,0)
  z = ffrep_sort_slot(target_cu,target_cv,target_cw,0,count)
  step = 0 ## i64
  while step < recipe[4]
    code = recipe[8+step] ## i64
    if code < 0 || fftc_apply_code(work_u,work_v,work_w,count,code,0-1) != 1
      return 0
    meta[0] += 1
    z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
    if ffrep_local_exact_shape(source_u,source_v,source_w,count,work_u,work_v,work_w,count,udim,vdim,wdim) != 1
      return 0
    meta[1] += 1
    step += 1
  if ffrep_state_equal(work_u,work_v,work_w,0,target_cu,target_cv,target_cw,0,count) != 1
    return 0
  meta[2] = 1
  if ffrep_local_exact_shape(source_u,source_v,source_w,count,work_u,work_v,work_w,count,udim,vdim,wdim) != 1
    return 0
  meta[3] = 1
  z = ffrep_copy_slot(work_u,work_v,work_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrep_replay_undo(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, recipe, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[]) i64
  if ffrep_recipe_valid(recipe) == 0 || source_count != recipe[2] || target_count != recipe[3]
    return 0
  count = source_count ## i64
  if out_u.size() < count || out_v.size() < count || out_w.size() < count || meta.size() < ffrep_replay_meta_size()
    return 0
  z = ffrep_clear(meta,ffrep_replay_meta_size()) ## i64
  udim = recipe[5] ## i64
  vdim = recipe[6] ## i64
  wdim = recipe[7] ## i64
  if ffrep_local_exact_shape(source_u,source_v,source_w,count,target_u,target_v,target_w,count,udim,vdim,wdim) != 1
    return 0
  meta[4] = 1
  work_u = i64[count]
  work_v = i64[count]
  work_w = i64[count]
  source_cu = i64[count]
  source_cv = i64[count]
  source_cw = i64[count]
  z = ffrep_copy_slot(target_u,target_v,target_w,0,count,work_u,work_v,work_w,0)
  z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
  z = ffrep_copy_slot(source_u,source_v,source_w,0,count,source_cu,source_cv,source_cw,0)
  z = ffrep_sort_slot(source_cu,source_cv,source_cw,0,count)
  step = 0 ## i64
  while step < recipe[4]
    code = recipe[18+step] ## i64
    if code < 0 || fftc_apply_code(work_u,work_v,work_w,count,code,0-1) != 1
      return 0
    meta[0] += 1
    z = ffrep_sort_slot(work_u,work_v,work_w,0,count)
    if ffrep_local_exact_shape(target_u,target_v,target_w,count,work_u,work_v,work_w,count,udim,vdim,wdim) != 1
      return 0
    meta[1] += 1
    step += 1
  if ffrep_state_equal(work_u,work_v,work_w,0,source_cu,source_cv,source_cw,0,count) != 1
    return 0
  meta[2] = 1
  if ffrep_local_exact_shape(target_u,target_v,target_w,count,work_u,work_v,work_w,count,udim,vdim,wdim) != 1
    return 0
  meta[3] = 1
  z = ffrep_copy_slot(work_u,work_v,work_w,0,count,out_u,out_v,out_w,0)
  count

-> ffrep_search_same_rank(source_u, source_v, source_w, source_count, target_u, target_v, target_w, target_count, udim, vdim, wdim, max_depth, node_cap, recipe, stats) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  if source_count < 2 || source_count > ffrep_max_count() || target_count != source_count
    return 0
  if max_depth < 1 || max_depth > ffrep_max_depth() || node_cap < 16 || node_cap > 65536
    return 0
  if recipe.size() < ffrep_recipe_size() || stats.size() < ffrep_stats_size()
    return 0
  if ffrep_terms_fit(source_u,source_v,source_w,source_count,udim,vdim,wdim) == 0 || ffrep_terms_fit(target_u,target_v,target_w,target_count,udim,vdim,wdim) == 0
    return 0
  z = ffrep_clear(recipe,ffrep_recipe_size()) ## i64
  z = ffrep_clear(stats,ffrep_stats_size())
  z = ffrep_fill(recipe,ffrep_recipe_size(),0-1)
  recipe[0] = 1
  recipe[1] = 0
  recipe[2] = source_count
  recipe[3] = target_count
  recipe[4] = 0
  recipe[5] = udim
  recipe[6] = vdim
  recipe[7] = wdim
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return 0
  stats[13] = 1

  source_cu = i64[source_count]
  source_cv = i64[source_count]
  source_cw = i64[source_count]
  target_cu = i64[source_count]
  target_cv = i64[source_count]
  target_cw = i64[source_count]
  z = ffrep_copy_slot(source_u,source_v,source_w,0,source_count,source_cu,source_cv,source_cw,0)
  z = ffrep_sort_slot(source_cu,source_cv,source_cw,0,source_count)
  z = ffrep_copy_slot(target_u,target_v,target_w,0,target_count,target_cu,target_cv,target_cw,0)
  z = ffrep_sort_slot(target_cu,target_cv,target_cw,0,target_count)
  if ffrep_state_equal(source_cu,source_cv,source_cw,0,target_cu,target_cv,target_cw,0,source_count) == 1
    return 0

  table_size = ffrep_table_size(node_cap) ## i64
  stats[14] = table_size
  fstates_u = i64[node_cap*source_count]
  fstates_v = i64[node_cap*source_count]
  fstates_w = i64[node_cap*source_count]
  bstates_u = i64[node_cap*source_count]
  bstates_v = i64[node_cap*source_count]
  bstates_w = i64[node_cap*source_count]
  fparents = i64[node_cap]
  bparents = i64[node_cap]
  fdepths = i64[node_cap]
  bdepths = i64[node_cap]
  fhashes = i64[node_cap]
  bhashes = i64[node_cap]
  ftable = i64[table_size]
  btable = i64[table_size]
  fmeta = i64[6]
  bmeta = i64[6]
  forward_limit = max_depth / 2 ## i64
  backward_limit = max_depth - forward_limit ## i64
  bnodes = ffrep_build_tree(target_cu,target_cv,target_cw,source_count,backward_limit,node_cap,bstates_u,bstates_v,bstates_w,bparents,bdepths,bhashes,btable,bmeta) ## i64
  if bnodes < 1
    return 0
  fnodes = ffrep_build_tree(source_cu,source_cv,source_cw,source_count,forward_limit,node_cap,fstates_u,fstates_v,fstates_w,fparents,fdepths,fhashes,ftable,fmeta) ## i64
  if fnodes < 1
    return 0
  stats[0] = fnodes
  stats[1] = bnodes
  stats[2] = fmeta[1]
  stats[3] = bmeta[1]
  stats[4] = fmeta[2] + bmeta[2]
  stats[5] = fmeta[3] + bmeta[3]
  if fmeta[4] != 0 || bmeta[4] != 0
    stats[10] = 1

  best_f = 0 - 1 ## i64
  best_b = 0 - 1 ## i64
  best_length = max_depth + 1 ## i64
  fi = 0 ## i64
  while fi < fnodes
    bi = ffrep_table_find(btable,table_size-1,bhashes,bstates_u,bstates_v,bstates_w,source_count,fstates_u,fstates_v,fstates_w,fi*source_count,fhashes[fi]) ## i64
    if bi >= 0
      length = fdepths[fi] + bdepths[bi] ## i64
      if length > 0 && length <= max_depth
        stats[6] += 1
        if length < best_length || (length == best_length && fdepths[fi] < fdepths[best_f]) || (length == best_length && fdepths[fi] == fdepths[best_f] && fi < best_f)
          best_f = fi
          best_b = bi
          best_length = length
    fi += 1
  if best_f < 0
    return 0

  path_u = i64[(max_depth+1)*source_count]
  path_v = i64[(max_depth+1)*source_count]
  path_w = i64[(max_depth+1)*source_count]
  chain = i64[max_depth+1]
  forward_depth = fdepths[best_f] ## i64
  pos = forward_depth ## i64
  current = best_f ## i64
  while pos >= 0
    chain[pos] = current
    current = fparents[current]
    pos -= 1
  pos = 0
  while pos <= forward_depth
    z = ffrep_copy_slot(fstates_u,fstates_v,fstates_w,chain[pos]*source_count,source_count,path_u,path_v,path_w,pos*source_count)
    pos += 1
  path_count = forward_depth + 1 ## i64
  current = best_b
  while bparents[current] >= 0
    current = bparents[current]
    z = ffrep_copy_slot(bstates_u,bstates_v,bstates_w,current*source_count,source_count,path_u,path_v,path_w,path_count*source_count)
    path_count += 1
  if path_count - 1 != best_length
    return 0

  recipe[4] = best_length
  step = 0 ## i64
  while step < best_length
    code = ffrep_find_transition(path_u,path_v,path_w,step*source_count,path_u,path_v,path_w,(step+1)*source_count,source_count) ## i64
    if code < 0
      return 0
    recipe[8+step] = code
    reverse = ffrep_find_transition(path_u,path_v,path_w,(best_length-step)*source_count,path_u,path_v,path_w,(best_length-step-1)*source_count,source_count) ## i64
    if reverse < 0
      return 0
    recipe[18+step] = reverse
    step += 1

  stats[7] = best_length
  stats[8] = fdepths[best_f]
  stats[9] = bdepths[best_b]
  replay_u = i64[source_count]
  replay_v = i64[source_count]
  replay_w = i64[source_count]
  replay_meta = i64[ffrep_replay_meta_size()]
  replayed = ffrep_replay_forward(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  if replayed != source_count || replay_meta[2] != 1 || replay_meta[3] != 1
    return 0
  stats[11] = 1
  undone = ffrep_replay_undo(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,recipe,replay_u,replay_v,replay_w,replay_meta) ## i64
  if undone != source_count || replay_meta[2] != 1 || replay_meta[3] != 1
    return 0
  stats[12] = 1
  stats[15] = 1
  best_length
