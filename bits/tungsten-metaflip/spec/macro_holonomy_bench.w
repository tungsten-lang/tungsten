# Bounded real-door decision benchmark for split-braid-merge holonomy.
#
# This is deliberately not a scheduler integration.  It samples deterministic
# four-term windows, chooses setup parts from another live factor (so the split
# creates a specific trigger), full-gates a bounded number of returned global
# splices, and measures whether endpoints escape ordinary/span-4 coverage.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_holonomy
use ../lib/metaflip/strategies/low_rank_shear

-> ffmhb_selected(selected, count, value) (i64[] i64 i64) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      found = 1
    i += 1
  found

-> ffmhb_make_window(rank, nonce, count, selected) (i64 i64 i64 i64[]) i64
  if count < 4 || count > 6 || rank < count || selected.size() < count
    return 0
  multipliers = i64[6]
  offsets = i64[6]
  multipliers[0] = 1
  multipliers[1] = 37
  multipliers[2] = 73
  multipliers[3] = 109
  multipliers[4] = 149
  multipliers[5] = 191
  offsets[0] = 0
  offsets[1] = 11
  offsets[2] = 17
  offsets[3] = 23
  offsets[4] = 29
  offsets[5] = 31
  i = 0 ## i64
  while i < count
    candidate = (nonce*multipliers[i]+offsets[i]) % rank ## i64
    while ffmhb_selected(selected,i,candidate) == 1
      candidate = (candidate+1) % rank
    selected[i] = candidate
    i += 1
  count

# Alternate hashed coverage with a greedy compatibility/XOR neighborhood.
# This avoids declaring a structured frontier negative merely because a
# pseudo-random window omitted the next trigger in its factor graph.
-> ffmhb_make_connected_window(us, vs, ws, rank, nonce, count, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if (nonce & 1) == 0
    return ffmhb_make_window(rank,nonce,count,selected)
  if count < 4 || count > 6 || rank < count || selected.size() < count
    return 0
  selected[0] = (nonce*97+13) % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    offset = (nonce*53+made*17) % rank ## i64
    ci = 0 ## i64
    while ci < rank
      candidate = (offset+ci) % rank ## i64
      if ffmhb_selected(selected,made,candidate) == 0
        score = 0 ## i64
        si = 0 ## i64
        while si < made
          axis = 0 ## i64
          while axis < 3
            candidate_factor = ffmh_axis_get(us,vs,ws,candidate,axis) ## i64
            if candidate_factor == ffmh_axis_get(us,vs,ws,selected[si],axis)
              score += 8
            sj = si + 1 ## i64
            while sj < made
              if candidate_factor == (ffmh_axis_get(us,vs,ws,selected[si],axis) ^ ffmh_axis_get(us,vs,ws,selected[sj],axis))
                score += 2
              sj += 1
            axis += 1
          si += 1
        if score > best_score
          best_score = score
          best = candidate
      ci += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  count

-> ffmhb_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[selected[i]]
    out_v[i] = vs[selected[i]]
    out_w[i] = ws[selected[i]]
    i += 1
  count

-> ffmhb_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return count
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < count && found < 0
    if fftc_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      found = i
    i += 1
  if found >= 0
    last = count - 1 ## i64
    us[found] = us[last]
    vs[found] = vs[last]
    ws[found] = ws[last]
    return count - 1
  if count >= capacity
    return 0 - count - 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

-> ffmhb_splice(us, vs, ws, rank, selected, selected_count, local_u, local_v, local_w, local_count, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffmhb_selected(selected,selected_count,i) == 0
      count = ffmhb_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count < 0
        return 0
    i += 1
  i = 0
  while i < local_count
    count = ffmhb_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count < 0
      return 0
    i += 1
  count

-> ffmhb_in_span(values, count, value) (i64[] i64 i64) i64
  basis = i64[count]
  basis_count = ffsr_make_basis(values,count,basis) ## i64
  span = i64[1 << basis_count]
  span_count = ffsr_enumerate_span(basis,basis_count,span) ## i64
  ffsr_contains(span,span_count,value)

# Decide whether the changed endpoint is already covered by an ordinary
# two-term flip or the complete span-3/span-4 lane.  Common terms are removed
# first, so a five-term window with only a three-term changed fringe is not
# incorrectly credited as a new macro family.
-> ffmhb_span4_delta_covered(source_u, source_v, source_w, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used = i64[out_count]
  delta_source_u = i64[source_count]
  delta_source_v = i64[source_count]
  delta_source_w = i64[source_count]
  delta_out_u = i64[out_count]
  delta_out_v = i64[out_count]
  delta_out_w = i64[out_count]
  source_delta = 0 ## i64
  i = 0 ## i64
  while i < source_count
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < out_count && found < 0
      if used[j] == 0 && fftc_same_term(source_u[i],source_v[i],source_w[i],out_u[j],out_v[j],out_w[j]) == 1
        found = j
      j += 1
    if found >= 0
      used[found] = 1
    else
      delta_source_u[source_delta] = source_u[i]
      delta_source_v[source_delta] = source_v[i]
      delta_source_w[source_delta] = source_w[i]
      source_delta += 1
    i += 1
  out_delta = 0 ## i64
  i = 0
  while i < out_count
    if used[i] == 0
      delta_out_u[out_delta] = out_u[i]
      delta_out_v[out_delta] = out_v[i]
      delta_out_w[out_delta] = out_w[i]
      out_delta += 1
    i += 1
  if source_delta == 2 && out_delta == 2
    return fflrs_is_one_flip(delta_source_u,delta_source_v,delta_source_w,2,delta_out_u,delta_out_v,delta_out_w)
  supported = 0 ## i64
  if source_delta == 3 && out_delta >= 2 && out_delta <= 4
    supported = 1
  if source_delta == 4 && (out_delta == 3 || out_delta == 4)
    supported = 1
  if supported == 0
    return 0
  covered = 1 ## i64
  i = 0
  while i < out_delta && covered == 1
    if ffmhb_in_span(delta_source_u,source_delta,delta_out_u[i]) == 0
      covered = 0
    if ffmhb_in_span(delta_source_v,source_delta,delta_out_v[i]) == 0
      covered = 0
    if ffmhb_in_span(delta_source_w,source_delta,delta_out_w[i]) == 0
      covered = 0
    i += 1
  covered

-> ffmhb_fingerprint(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  fingerprint = 0 ## i64
  i = 0 ## i64
  while i < count
    fingerprint = fingerprint ^ ffw_term_zobrist(us[i],vs[i],ws[i])
    i += 1
  fingerprint

-> ffmhb_unique_add(fingerprints, count, capacity, value) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if fingerprints[i] == value
      return count
    i += 1
  if count < capacity
    fingerprints[count] = value
    return count + 1
  count

-> ffmhb_run_mode(label, path, n, m, p, rectangular, window_size, windows, max_edges, gate_cap, selection_mode) (String String i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n,m,p)
  state = i64[ffw_state_size(capacity)]
  rank = 0 ## i64
  if rectangular == 0
    rank = ffw_load_scheme_cap(state,path,n,capacity,91001+n,0,1,1,1)
    if rank < 1 || ffw_verify_best_exact(state,n) != 1
      << "MACRO_HOLONOMY tensor="+label+" error=load"
      return 0
  else
    rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,91001+n+m+p,0,1,1,1)
    if rank < 1 || ffr_verify_best_exact(state,n,m,p) != 1
      << "MACRO_HOLONOMY tensor="+label+" error=load"
      return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state,us,vs,ws) ## i64
  source_density = fftc_density(us,vs,ws,rank) ## i64
  fingerprints = i64[windows*window_size*3+1]
  fingerprint_count = 0 ## i64
  setups = 0 ## i64
  legal_edges = 0 ## i64
  closures = 0 ## i64
  local_changed = 0 ## i64
  hits = 0 ## i64
  one_flip = 0 ## i64
  span_covered = 0 ## i64
  beyond_span = 0 ## i64
  full_gates = 0 ## i64
  gate_failures = 0 ## i64
  beyond_gates = 0 ## i64
  beyond_gate_failures = 0 ## i64
  rank_wins = 0 ## i64
  density_wins = 0 ## i64
  best_rank = rank ## i64
  best_density = source_density ## i64
  beyond_best_rank = rank ## i64
  beyond_best_density = 1 << 30 ## i64
  beyond_density_wins = 0 ## i64
  max_distance = 0 ## i64
  start_ms = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows
    selected = i64[window_size]
    z = ffmhb_make_connected_window(us,vs,ws,rank,window,window_size,selected)
    local_u = i64[window_size]
    local_v = i64[window_size]
    local_w = i64[window_size]
    z = ffmhb_capture(us,vs,ws,selected,window_size,local_u,local_v,local_w)
    split_source = 0 ## i64
    while split_source < window_size
      axis = 0 ## i64
      while axis < 3
        target = (split_source+1+(window%3)) % window_size ## i64
        if target == split_source
          target = (target+1) % window_size
        part = ffmh_axis_get(local_u,local_v,local_w,target,axis) ## i64
        factor = ffmh_axis_get(local_u,local_v,local_w,split_source,axis) ## i64
        if part != 0 && part != factor
          setups += 1
          out_u = i64[window_size+1]
          out_v = i64[window_size+1]
          out_w = i64[window_size+1]
          recipe = i64[13]
          stats = i64[12]
          out_count = ffmh_search_mode(local_u,local_v,local_w,window_size,split_source,axis,part,4,max_edges,selection_mode,out_u,out_v,out_w,recipe,stats) ## i64
          legal_edges += stats[1]
          closures += stats[2]
          local_changed += stats[3]
          if out_count > 0 && stats[10] == 1
            hits += 1
            if stats[6] > max_distance
              max_distance = stats[6]
            if out_count == window_size && fflrs_is_one_flip(local_u,local_v,local_w,window_size,out_u,out_v,out_w) == 1
              one_flip += 1
            covered = ffmhb_span4_delta_covered(local_u,local_v,local_w,window_size,out_u,out_v,out_w,out_count) ## i64
            if covered == 1
              span_covered += 1
            else
              beyond_span += 1
            candidate_u = i64[capacity]
            candidate_v = i64[capacity]
            candidate_w = i64[capacity]
            candidate_rank = ffmhb_splice(us,vs,ws,rank,selected,window_size,out_u,out_v,out_w,out_count,candidate_u,candidate_v,candidate_w,capacity) ## i64
            if candidate_rank > 0
              fingerprint_count = ffmhb_unique_add(fingerprints,fingerprint_count,fingerprints.size(),ffmhb_fingerprint(candidate_u,candidate_v,candidate_w,candidate_rank))
              candidate_density = fftc_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
              if candidate_rank < best_rank
                best_rank = candidate_rank
                best_density = candidate_density
              if candidate_rank == best_rank && candidate_density < best_density
                best_density = candidate_density
              if candidate_rank < rank
                rank_wins += 1
              if candidate_rank == rank && candidate_density < source_density
                density_wins += 1
              must_gate = 0 ## i64
              if full_gates < gate_cap || candidate_rank < rank || covered == 0
                must_gate = 1
              if must_gate == 1
                child = i64[ffw_state_size(capacity)]
                loaded = 0 ## i64
                exact = 0 ## i64
                if rectangular == 0
                  loaded = ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,92001+full_gates,0,1,1,1)
                  if loaded == candidate_rank
                    exact = ffw_verify_best_exact(child,n)
                else
                  loaded = ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,92001+full_gates,0,1,1,1)
                  if loaded == candidate_rank
                    exact = ffr_verify_best_exact(child,n,m,p)
                full_gates += 1
                if covered == 0
                  beyond_gates += 1
                if exact != 1
                  gate_failures += 1
                  if covered == 0
                    beyond_gate_failures += 1
                if exact == 1 && covered == 0 && beyond_gates == 1
                  output_path = "/tmp/metaflip_macro_holonomy_"+label+".txt"
                  if rectangular == 0
                    dumped = ffw_dump_best(child,output_path) ## i64
                  else
                    dumped = ffr_dump_best(child,output_path) ## i64
                  << "MACRO_HOLONOMY_DOOR tensor="+label+" path="+output_path+" rank="+candidate_rank.to_s()+" density="+candidate_density.to_s()+" local_distance="+stats[6].to_s()+" depth="+stats[8].to_s()+" recipe="+recipe[0].to_s()+","+recipe[1].to_s()+","+recipe[2].to_s()+","+recipe[3].to_s()+","+recipe[4].to_s()+","+recipe[5].to_s()+","+recipe[6].to_s()+","+recipe[7].to_s()+","+recipe[8].to_s()+","+recipe[9].to_s()+","+recipe[10].to_s()
                if exact == 1 && covered == 0
                  if candidate_rank == rank && candidate_density < source_density
                    beyond_density_wins += 1
                  better_beyond = 0 ## i64
                  if candidate_rank < beyond_best_rank
                    better_beyond = 1
                  if candidate_rank == beyond_best_rank && candidate_density < beyond_best_density
                    better_beyond = 1
                  if better_beyond == 1
                    beyond_best_rank = candidate_rank
                    beyond_best_density = candidate_density
                    best_beyond_path = "/tmp/metaflip_macro_holonomy_"+label+"_best.txt"
                    if rectangular == 0
                      dumped = ffw_dump_best(child,best_beyond_path)
                    else
                      dumped = ffr_dump_best(child,best_beyond_path)
        axis += 1
      split_source += 1
    window += 1
  elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
  << "MACRO_HOLONOMY tensor="+label+" mode="+selection_mode.to_s()+" rank="+rank.to_s()+" density="+source_density.to_s()+" k="+window_size.to_s()+" windows="+windows.to_s()+" setups="+setups.to_s()+" legal_edges="+legal_edges.to_s()+" closures="+closures.to_s()+" changed="+local_changed.to_s()+" hits="+hits.to_s()+" unique="+fingerprint_count.to_s()+" one_flip="+one_flip.to_s()+" span4="+span_covered.to_s()+" beyond_span4="+beyond_span.to_s()+" gates="+full_gates.to_s()+" gate_fail="+gate_failures.to_s()+" beyond_gates="+beyond_gates.to_s()+" beyond_gate_fail="+beyond_gate_failures.to_s()+" rank_wins="+rank_wins.to_s()+" density_wins="+density_wins.to_s()+" beyond_density_wins="+beyond_density_wins.to_s()+" best_rank="+best_rank.to_s()+" best_density="+best_density.to_s()+" beyond_best_rank="+beyond_best_rank.to_s()+" beyond_best_density="+beyond_best_density.to_s()+" max_local_distance="+max_distance.to_s()+" ms="+elapsed_ms.to_s()
  1

-> ffmhb_run(label, path, n, m, p, rectangular, window_size, windows, max_edges, gate_cap) (String String i64 i64 i64 i64 i64 i64 i64 i64) i64
  ffmhb_run_mode(label,path,n,m,p,rectangular,window_size,windows,max_edges,gate_cap,0)

# Short matched continuation is evidence about basin utility, not merely
# endpoint existence.  Both arms receive identical rectangular controls and
# move budgets; only the exact initial presentation differs.
-> ffmhb_continue_225(source_path, door_path, trials, moves) (String String i64 i64) i64
  n = 2 ## i64
  m = 2 ## i64
  p = 5 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  control_drops = 0 ## i64
  door_drops = 0 ## i64
  control_best = 18 ## i64
  door_best = 18 ## i64
  control_bits = 1 << 30 ## i64
  door_bits = 1 << 30 ## i64
  start_ms = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 97001 + trial*1009 ## i64
    workq = moves / 10 ## i64
    wanderq = moves / 25 ## i64
    control = i64[ffr_state_size(capacity)]
    door = i64[ffr_state_size(capacity)]
    control_rank = ffr_load_scheme_cap(control,source_path,n,m,p,capacity,seed,4,4,workq,wanderq) ## i64
    door_rank = ffr_load_scheme_cap(door,door_path,n,m,p,capacity,seed,4,4,workq,wanderq) ## i64
    if control_rank != 18 || door_rank != 18 || ffr_verify_best_exact(control,n,m,p) != 1 || ffr_verify_best_exact(door,n,m,p) != 1
      << "MACRO_HOLONOMY_CONTINUE tensor=2x2x5 error=load"
      return 0
    z = ffr_walk(control,moves) ## i64
    z = ffr_walk(door,moves)
    if ffr_best_rank(control) < 18
      control_drops += 1
    if ffr_best_rank(door) < 18
      door_drops += 1
    if ffr_best_rank(control) < control_best
      control_best = ffr_best_rank(control)
    if ffr_best_rank(door) < door_best
      door_best = ffr_best_rank(door)
    if ffr_best_bits(control) < control_bits
      control_bits = ffr_best_bits(control)
    if ffr_best_bits(door) < door_bits
      door_bits = ffr_best_bits(door)
    trial += 1
  elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
  << "MACRO_HOLONOMY_CONTINUE tensor=2x2x5 trials="+trials.to_s()+" moves_per_arm="+moves.to_s()+" control_drops="+control_drops.to_s()+" door_drops="+door_drops.to_s()+" control_best="+control_best.to_s()+" door_best="+door_best.to_s()+" control_bits="+control_bits.to_s()+" door_bits="+door_bits.to_s()+" ms="+elapsed_ms.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffmhb_run("4x4x4",root+"matmul_4x4_rank47_d450_gf2.txt",4,4,4,0,5,24,8000,8) ## i64
z = ffmhb_run("5x5x5",root+"matmul_5x5_rank93_d983_global_isotropy_gf2.txt",5,5,5,0,5,24,8000,8)
z = ffmhb_run("6x6x6",root+"matmul_6x6_rank153_d1860_global_isotropy_gf2.txt",6,6,6,0,5,24,8000,8)
z = ffmhb_run("7x7x7",root+"matmul_7x7_rank247_d3098_global_isotropy_gf2.txt",7,7,7,0,5,24,8000,8)
z = ffmhb_run("2x2x5",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5,1,5,32,8000,8)
z = ffmhb_run("2x5x6",root+"matmul_2x5x6_rank47_catalog_gf2.txt",2,5,6,1,5,32,8000,8)
z = ffmhb_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,5,24,8000,8)
z = ffmhb_run("4x4x4-k6",root+"matmul_4x4_rank47_d450_gf2.txt",4,4,4,0,6,16,16000,8)
z = ffmhb_run("5x5x5-k6",root+"matmul_5x5_rank93_d983_global_isotropy_gf2.txt",5,5,5,0,6,16,16000,8)
z = ffmhb_run("6x6x6-k6",root+"matmul_6x6_rank153_d1860_global_isotropy_gf2.txt",6,6,6,0,6,16,16000,8)
z = ffmhb_run("7x7x7-k6",root+"matmul_7x7_rank247_d3098_global_isotropy_gf2.txt",7,7,7,0,6,16,16000,8)
z = ffmhb_run("2x2x5-k6",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5,1,6,24,16000,8)
z = ffmhb_run("2x5x6-k6",root+"matmul_2x5x6_rank47_catalog_gf2.txt",2,5,6,1,6,16,16000,8)
z = ffmhb_run("5x5x5-leader",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,5,24,8000,8)
z = ffmhb_run("5x5x5-leader-k6",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,6,16,16000,8)
z = ffmhb_continue_225(root+"matmul_2x2x5_rank18_d84_gf2.txt","/tmp/metaflip_macro_holonomy_2x2x5-k6.txt",8,5000000)

# Goal-scored matched enumerations.  Mode 1 asks for the sparsest exact close;
# mode 2 asks for the close with the most downstream pair-flip doors.
z = ffmhb_run_mode("2x2x5-density-goal",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5,1,6,24,16000,8,1)
z = ffmhb_run_mode("2x2x5-pressure-goal",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5,1,6,24,16000,8,2)
z = ffmhb_run_mode("4x4x5-density-goal",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,5,24,8000,8,1)
z = ffmhb_run_mode("4x4x5-pressure-goal",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,5,24,8000,8,2)
z = ffmhb_run_mode("4x5x7-density-goal",root+"matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt",4,5,7,1,6,16,16000,8,1)
z = ffmhb_run_mode("4x5x7-pressure-goal",root+"matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt",4,5,7,1,6,16,16000,8,2)
z = ffmhb_run_mode("5x5x5-leader-density-goal",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,6,16,16000,8,1)
z = ffmhb_run_mode("5x5x5-leader-pressure-goal",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,6,16,16000,8,2)
density_goal_path = "/tmp/metaflip_macro_holonomy_2x2x5-density-goal_best.txt"
pressure_goal_path = "/tmp/metaflip_macro_holonomy_2x2x5-pressure-goal_best.txt"
if read_file(density_goal_path) != nil
  z = ffmhb_continue_225(root+"matmul_2x2x5_rank18_d84_gf2.txt",density_goal_path,8,5000000)
if read_file(pressure_goal_path) != nil
  z = ffmhb_continue_225(root+"matmul_2x2x5_rank18_d84_gf2.txt",pressure_goal_path,8,5000000)
