# Bounded real-frontier decision benchmark for the Rubik-style duplicate goal.
# This is offline evidence only; it does not register a CPU or GPU pool lane.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_goal_beam

-> ffmrgb_selected(selected, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      return 1
    i += 1
  0

# Select a small compatibility-connected fringe, rotating the anchor so the
# two windows do not simply repeat the same high-pressure door.
-> ffmrgb_window(us, vs, ws, rank, nonce, count, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank < count || count < 4 || count > 8
    return 0
  selected[0] = (nonce*97+13) % rank
  made = 1 ## i64
  while made < count
    best = 0 - 1 ## i64
    best_score = 0 - 9223372036854775807 ## i64
    offset = (nonce*53+made*17) % rank ## i64
    scan = 0 ## i64
    while scan < rank
      candidate = (offset+scan) % rank ## i64
      if ffmrgb_selected(selected,made,candidate) == 0
        score = 0 ## i64
        prior = 0 ## i64
        while prior < made
          axis = 0 ## i64
          while axis < 3
            factor = ffmh_axis_get(us,vs,ws,candidate,axis) ## i64
            other = ffmh_axis_get(us,vs,ws,selected[prior],axis) ## i64
            if factor == other
              score += 8
            score -= ffw_popcount(factor ^ other)
            axis += 1
          prior += 1
        if score > best_score
          best_score = score
          best = candidate
      scan += 1
    if best < 0
      return 0
    selected[made] = best
    made += 1
  count

-> ffmrgb_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[selected[i]]
    out_v[i] = vs[selected[i]]
    out_w[i] = ws[selected[i]]
    i += 1
  count

# Choose the non-setup child closest to literal equality with the new split
# label.  All three factor mismatches are part of the score.
-> ffmrgb_duplicate_target(root_u, root_v, root_w, source_count, split_source) (i64[] i64[] i64[] i64 i64) i64
  new_label = source_count ## i64
  best = 0 - 1 ## i64
  best_score = 0 - 9223372036854775807 ## i64
  second = 0 ## i64
  while second < source_count
    if second != split_source
      readiness = ffmgb_readiness(root_u,root_v,root_w,0,new_label,second,3) ## i64
      mismatch = ffmgb_mismatch_bits(root_u,root_v,root_w,0,new_label,second,3) ## i64
      pressure = ffmgb_target_pressure(root_u,root_v,root_w,0,source_count+1,new_label,second) ## i64
      score = readiness*1000000 - mismatch*1000 + pressure ## i64
      if score > best_score
        best_score = score
        best = second
    second += 1
  best

-> ffmrgb_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
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

-> ffmrgb_splice(us, vs, ws, rank, selected, selected_count, local_u, local_v, local_w, local_count, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffmrgb_selected(selected,selected_count,i) == 0
      count = ffmrgb_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count < 0
        return 0
    i += 1
  i = 0
  while i < local_count
    count = ffmrgb_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count < 0
      return 0
    i += 1
  count

-> ffmrgb_run(label, path, n, m, p, rectangular, windows, max_depth, beam_width) (String String i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n,m,p)
  state = i64[ffw_state_size(capacity)]
  rank = 0 ## i64
  if rectangular == 0
    rank = ffw_load_scheme_cap(state,path,n,capacity,106001+n,0,1,1,1)
    if rank < 1 || ffw_verify_best_exact(state,n) != 1
      << "MACRO_RANKDROP_GOAL tensor=" + label + " error=load"
      return 0
  if rectangular != 0
    rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,106001+n+m+p,0,1,1,1)
    if rank < 1 || ffr_verify_best_exact(state,n,m,p) != 1
      << "MACRO_RANKDROP_GOAL tensor=" + label + " error=load"
      return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state,us,vs,ws) ## i64
  window_size = 6 ## i64
  searches = 0 ## i64
  codes = 0 ## i64
  legal = 0 ## i64
  revisits = 0 ## i64
  visited = 0 ## i64
  ready3 = 0 ## i64
  local_drops = 0 ## i64
  full_gates = 0 ## i64
  full_drops = 0 ## i64
  gate_failures = 0 ## i64
  best_depth = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows
    selected = i64[window_size]
    z = ffmrgb_window(us,vs,ws,rank,window,window_size,selected)
    local_u = i64[window_size]
    local_v = i64[window_size]
    local_w = i64[window_size]
    z = ffmrgb_capture(us,vs,ws,selected,window_size,local_u,local_v,local_w)
    split_source = (window*3+1) % window_size ## i64
    split_axis = 0 ## i64
    while split_axis < 3
      part_source = (split_source+1+window) % window_size ## i64
      if part_source == split_source
        part_source = (part_source+1) % window_size
      part = ffmh_axis_get(local_u,local_v,local_w,part_source,split_axis) ## i64
      factor = ffmh_axis_get(local_u,local_v,local_w,split_source,split_axis) ## i64
      if part != 0 && part != factor
        root_u = i64[window_size+1]
        root_v = i64[window_size+1]
        root_w = i64[window_size+1]
        z = ffmh_copy(local_u,local_v,local_w,window_size,root_u,root_v,root_w)
        if ffmh_split_labeled(root_u,root_v,root_w,window_size,window_size+1,split_source,split_axis,part) == window_size+1
          target = ffmrgb_duplicate_target(root_u,root_v,root_w,window_size,split_source) ## i64
          if target >= 0
            searches += 1
            out_u = i64[window_size+1]
            out_v = i64[window_size+1]
            out_w = i64[window_size+1]
            recipe = i64[20]
            stats = i64[16]
            out_count = ffmgb_search_annihilation(local_u,local_v,local_w,window_size,split_source,split_axis,part,window_size,target,2,max_depth,beam_width,out_u,out_v,out_w,recipe,stats) ## i64
            codes += stats[0]
            legal += stats[1]
            revisits += stats[2]
            visited += stats[13]
            ready3 += stats[4]
            if out_count > 0
              local_drops += 1
              if best_depth == 0 || recipe[3] < best_depth
                best_depth = recipe[3]
              candidate_u = i64[capacity]
              candidate_v = i64[capacity]
              candidate_w = i64[capacity]
              candidate_rank = ffmrgb_splice(us,vs,ws,rank,selected,window_size,out_u,out_v,out_w,out_count,candidate_u,candidate_v,candidate_w,capacity) ## i64
              if candidate_rank > 0
                child = i64[ffw_state_size(capacity)]
                exact = 0 ## i64
                if rectangular == 0
                  loaded = ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,107001+full_gates,0,1,1,1) ## i64
                  if loaded == candidate_rank
                    exact = ffw_verify_best_exact(child,n)
                if rectangular != 0
                  loaded = ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,107001+full_gates,0,1,1,1)
                  if loaded == candidate_rank
                    exact = ffr_verify_best_exact(child,n,m,p)
                full_gates += 1
                if exact == 1 && candidate_rank < rank
                  full_drops += 1
                if exact != 1
                  gate_failures += 1
      split_axis += 1
    window += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "MACRO_RANKDROP_GOAL tensor=" + label + " rank=" + rank.to_s() + " windows=" + windows.to_s() + " searches=" + searches.to_s() + " depth=2-" + max_depth.to_s() + " beam=" + beam_width.to_s() + " codes=" + codes.to_s() + " legal=" + legal.to_s() + " revisits=" + revisits.to_s() + " visited=" + visited.to_s() + " ready3=" + ready3.to_s() + " local_drops=" + local_drops.to_s() + " full_gates=" + full_gates.to_s() + " full_drops=" + full_drops.to_s() + " gate_fail=" + gate_failures.to_s() + " best_depth=" + best_depth.to_s() + " ms=" + elapsed.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffmrgb_run("2x2x7",root+"matmul_2x2x7_rank25_catalog_gf2.txt",2,2,7,1,32,8,128) ## i64
z = ffmrgb_run("2x2x9",root+"matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt",2,2,9,1,32,8,128)
z = ffmrgb_run("3x3",root+"matmul_3x3_rank23_d139_gf2.txt",3,3,3,0,32,8,128)
