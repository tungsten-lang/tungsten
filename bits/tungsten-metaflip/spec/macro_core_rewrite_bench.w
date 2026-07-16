# Offline decision benchmark for constraint-directed chosen-core rewrites.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_core_rewrite
use ../lib/metaflip/strategies/low_rank_shear

-> ffmcrb_selected(selected, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      return 1
    i += 1
  0

-> ffmcrb_window(us, vs, ws, rank, nonce, count, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank < count || count < 4 || count > 8
    return 0
  selected[0] = (nonce*97+13) % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 1 ## i64
    offset = (nonce*53+made*17) % rank ## i64
    candidate_offset = 0 ## i64
    while candidate_offset < rank
      candidate = (offset+candidate_offset) % rank ## i64
      if ffmcrb_selected(selected,made,candidate) == 0
        score = 0 ## i64
        prior = 0 ## i64
        while prior < made
          axis = 0 ## i64
          while axis < 3
            factor = ffmh_axis_get(us,vs,ws,candidate,axis) ## i64
            if factor == ffmh_axis_get(us,vs,ws,selected[prior],axis)
              score += 8
            other = prior + 1 ## i64
            while other < made
              if factor == (ffmh_axis_get(us,vs,ws,selected[prior],axis) ^ ffmh_axis_get(us,vs,ws,selected[other],axis))
                score += 2
              other += 1
            axis += 1
          prior += 1
        if score > best_score
          best_score = score
          best = candidate
      candidate_offset += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  count

-> ffmcrb_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[selected[i]]
    out_v[i] = vs[selected[i]]
    out_w[i] = ws[selected[i]]
    i += 1
  count

-> ffmcrb_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return 0 - count - 1
  i = 0 ## i64
  while i < count
    if fftc_same_term(us[i],vs[i],ws[i],u,v,w) == 1
      last = count - 1 ## i64
      us[i] = us[last]
      vs[i] = vs[last]
      ws[i] = ws[last]
      return count - 1
    i += 1
  if count >= capacity
    return 0 - count - 1
  us[count] = u
  vs[count] = v
  ws[count] = w
  count + 1

-> ffmcrb_splice(us, vs, ws, rank, selected, selected_count, local_u, local_v, local_w, local_count, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffmcrb_selected(selected,selected_count,i) == 0
      count = ffmcrb_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count < 0
        return 0
    i += 1
  i = 0
  while i < local_count
    count = ffmcrb_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count < 0
      return 0
    i += 1
  count

-> ffmcrb_in_span(values, count, value) (i64[] i64 i64) i64
  basis = i64[count]
  basis_count = ffsr_make_basis(values,count,basis) ## i64
  span = i64[1 << basis_count]
  span_count = ffsr_enumerate_span(basis,basis_count,span) ## i64
  ffsr_contains(span,span_count,value)

-> ffmcrb_span4_covered(source_u, source_v, source_w, source_count, out_u, out_v, out_w, out_count) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  used = i64[out_count]
  du = i64[source_count]
  dv = i64[source_count]
  dw = i64[source_count]
  ou = i64[out_count]
  ov = i64[out_count]
  ow = i64[out_count]
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
      du[source_delta] = source_u[i]
      dv[source_delta] = source_v[i]
      dw[source_delta] = source_w[i]
      source_delta += 1
    i += 1
  out_delta = 0 ## i64
  i = 0
  while i < out_count
    if used[i] == 0
      ou[out_delta] = out_u[i]
      ov[out_delta] = out_v[i]
      ow[out_delta] = out_w[i]
      out_delta += 1
    i += 1
  if source_delta == 2 && out_delta == 2
    return fflrs_is_one_flip(du,dv,dw,2,ou,ov,ow)
  supported = 0 ## i64
  if source_delta == 3 && out_delta >= 2 && out_delta <= 4
    supported = 1
  if source_delta == 4 && (out_delta == 3 || out_delta == 4)
    supported = 1
  if supported == 0
    return 0
  i = 0
  while i < out_delta
    if ffmcrb_in_span(du,source_delta,ou[i]) == 0 || ffmcrb_in_span(dv,source_delta,ov[i]) == 0 || ffmcrb_in_span(dw,source_delta,ow[i]) == 0
      return 0
    i += 1
  1

-> ffmcrb_run(label, path, n, m, p, rectangular, windows, split_choices, min_depth, max_depth, beam_width, selection_mode) (String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n,m,p)
  state = i64[ffw_state_size(capacity)]
  rank = 0 ## i64
  if rectangular == 0
    rank = ffw_load_scheme_cap(state,path,n,capacity,96001+n,0,1,1,1)
    if rank < 1 || ffw_verify_best_exact(state,n) != 1
      << "MACRO_CORE_REWRITE tensor="+label+" error=load"
      return 0
  if rectangular != 0
    rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,96001+n+m+p,0,1,1,1)
    if rank < 1 || ffr_verify_best_exact(state,n,m,p) != 1
      << "MACRO_CORE_REWRITE tensor="+label+" error=load"
      return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state,us,vs,ws) ## i64
  source_density = fftc_density(us,vs,ws,rank) ## i64
  window_size = 6 ## i64
  searches = 0 ## i64
  codes = 0 ## i64
  legal = 0 ## i64
  revisits = 0 ## i64
  retained = 0 ## i64
  visited = 0 ## i64
  ready = 0 ## i64
  local_hits = 0 ## i64
  full_gates = 0 ## i64
  gate_failures = 0 ## i64
  target_failures = 0 ## i64
  span4 = 0 ## i64
  beyond = 0 ## i64
  unique = 0 ## i64
  fingerprints = i64[windows*split_choices*3+1]
  density_wins = 0 ## i64
  rank_wins = 0 ## i64
  best_rank = rank ## i64
  best_density = source_density ## i64
  best_distance = 0 ## i64
  best_depth = 0 ## i64
  best_beyond_found = 0 ## i64
  best_beyond_path = "/tmp/metaflip_macro_core_rewrite_"+label+"_m"+selection_mode.to_s()+"_best.txt"
  start_ms = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows
    selected = i64[window_size]
    z = ffmcrb_window(us,vs,ws,rank,window,window_size,selected)
    local_u = i64[window_size]
    local_v = i64[window_size]
    local_w = i64[window_size]
    z = ffmcrb_capture(us,vs,ws,selected,window_size,local_u,local_v,local_w)
    target_index = 0 ## i64
    split_choice = 0 ## i64
    while split_choice < split_choices
      split_source = 0 ## i64
      if split_choice > 0
        split_source = 1 + ((window*3+split_choice*5) % (window_size-1))
      split_axis = 0 ## i64
      while split_axis < 3
        part_source = 1 + ((window+split_choice+split_axis) % (window_size-1)) ## i64
        if part_source == split_source
          part_source = 1 + (part_source % (window_size-1))
        part = ffmh_axis_get(local_u,local_v,local_w,part_source,split_axis) ## i64
        factor = ffmh_axis_get(local_u,local_v,local_w,split_source,split_axis) ## i64
        if part != 0 && part != factor
          searches += 1
          out_u = i64[window_size+1]
          out_v = i64[window_size+1]
          out_w = i64[window_size+1]
          recipe = i64[20]
          stats = i64[16]
          out_count = ffmcr_search(local_u,local_v,local_w,window_size,target_index,split_source,split_axis,part,min_depth,max_depth,beam_width,selection_mode,out_u,out_v,out_w,recipe,stats) ## i64
          codes += stats[0]
          legal += stats[1]
          revisits += stats[2]
          retained += stats[3]
          ready += stats[4]
          visited += stats[13]
          if out_count > 0 && stats[12] == 1
            local_hits += 1
            if ffmcr_contains_term(out_u,out_v,out_w,0,out_count,local_u[target_index],local_v[target_index],local_w[target_index]) != 0
              target_failures += 1
            covered = ffmcrb_span4_covered(local_u,local_v,local_w,window_size,out_u,out_v,out_w,out_count) ## i64
            if covered == 1
              span4 += 1
            else
              beyond += 1
            candidate_u = i64[capacity]
            candidate_v = i64[capacity]
            candidate_w = i64[capacity]
            candidate_rank = ffmcrb_splice(us,vs,ws,rank,selected,window_size,out_u,out_v,out_w,out_count,candidate_u,candidate_v,candidate_w,capacity) ## i64
            if candidate_rank > 0
              child = i64[ffw_state_size(capacity)]
              loaded = 0 ## i64
              exact = 0 ## i64
              if rectangular == 0
                loaded = ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,97001+full_gates,0,1,1,1)
                if loaded == candidate_rank
                  exact = ffw_verify_best_exact(child,n)
              if rectangular != 0
                loaded = ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,97001+full_gates,0,1,1,1)
                if loaded == candidate_rank
                  exact = ffr_verify_best_exact(child,n,m,p)
              full_gates += 1
              if exact != 1
                gate_failures += 1
              if exact == 1
                fp = 0 ## i64
                term = 0 ## i64
                while term < candidate_rank
                  fp = fp ^ ffw_term_zobrist(candidate_u[term],candidate_v[term],candidate_w[term])
                  term += 1
                seen_fp = 0 ## i64
                fi = 0 ## i64
                while fi < unique
                  if fingerprints[fi] == fp
                    seen_fp = 1
                  fi += 1
                if seen_fp == 0 && unique < fingerprints.size()
                  fingerprints[unique] = fp
                  unique += 1
                density = fftc_density(candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
                distance = ffmh_distance(us,vs,ws,rank,candidate_u,candidate_v,candidate_w,candidate_rank) ## i64
                if candidate_rank < rank
                  rank_wins += 1
                if candidate_rank == rank && density < source_density
                  density_wins += 1
                better = 0 ## i64
                if covered == 0
                  if best_beyond_found == 0 || candidate_rank < best_rank
                    better = 1
                  if candidate_rank == best_rank && density < best_density
                    better = 1
                  if candidate_rank == best_rank && density == best_density && distance > best_distance
                    better = 1
                if better == 1
                  best_beyond_found = 1
                  best_rank = candidate_rank
                  best_density = density
                  best_distance = distance
                  best_depth = recipe[3]
                  if rectangular == 0
                    dumped = ffw_dump_best(child,best_beyond_path) ## i64
                  if rectangular != 0
                    dumped = ffr_dump_best(child,best_beyond_path)
        split_axis += 1
      split_choice += 1
    window += 1
  elapsed_ms = ccall("__w_clock_ms") - start_ms ## i64
  << "MACRO_CORE_REWRITE tensor="+label+" mode="+selection_mode.to_s()+" rank="+rank.to_s()+" density="+source_density.to_s()+" windows="+windows.to_s()+" searches="+searches.to_s()+" depth="+min_depth.to_s()+"-"+max_depth.to_s()+" beam="+beam_width.to_s()+" codes="+codes.to_s()+" legal="+legal.to_s()+" revisits="+revisits.to_s()+" retained="+retained.to_s()+" visited="+visited.to_s()+" ready="+ready.to_s()+" local_hits="+local_hits.to_s()+" target_fail="+target_failures.to_s()+" gates="+full_gates.to_s()+" gate_fail="+gate_failures.to_s()+" unique="+unique.to_s()+" span4="+span4.to_s()+" beyond_span4="+beyond.to_s()+" rank_wins="+rank_wins.to_s()+" density_wins="+density_wins.to_s()+" best_rank="+best_rank.to_s()+" best_density="+best_density.to_s()+" best_distance="+best_distance.to_s()+" best_depth="+best_depth.to_s()+" best_path="+best_beyond_path+" ms="+elapsed_ms.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffmcrb_run("5x5-d967",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,4,2,5,8,128,0) ## i64
z = ffmcrb_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,4,2,5,8,128,0)
z = ffmcrb_run("2x5x6",root+"matmul_2x5x6_rank47_catalog_gf2.txt",2,5,6,1,4,2,5,8,128,0)
z = ffmcrb_run("5x5-d967",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5,5,5,0,4,2,5,8,128,1)
z = ffmcrb_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,4,2,5,8,128,1)
z = ffmcrb_run("2x5x6",root+"matmul_2x5x6_rank47_catalog_gf2.txt",2,5,6,1,4,2,5,8,128,1)
