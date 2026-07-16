# Bounded real-frontier decision benchmark for the coupled rank-two close.
# Discovery mode is deliberately more permissive than a production prescribed
# goal: every retained state is checked for any two exact doublets.  A miss is
# therefore evidence against this bounded setup family, not a lower bound.

use ../lib/metaflip/rect
use ../lib/metaflip/strategies/macro_double_annihilation

-> ffmdab_selected(selected, count, value) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    if selected[i] == value
      return 1
    i += 1
  0

-> ffmdab_window(us, vs, ws, rank, nonce, count, selected) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  if rank < count || count < 4 || count > 7
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
      if ffmdab_selected(selected,made,candidate) == 0
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

-> ffmdab_capture(us, vs, ws, selected, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    out_u[i] = us[selected[i]]
    out_v[i] = vs[selected[i]]
    out_w[i] = ws[selected[i]]
    i += 1
  count

-> ffmdab_toggle(us, vs, ws, count, capacity, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
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

-> ffmdab_splice(us, vs, ws, rank, selected, selected_count, local_u, local_v, local_w, local_count, out_u, out_v, out_w, capacity) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffmdab_selected(selected,selected_count,i) == 0
      count = ffmdab_toggle(out_u,out_v,out_w,count,capacity,us[i],vs[i],ws[i])
      if count < 0
        return 0
    i += 1
  i = 0
  while i < local_count
    count = ffmdab_toggle(out_u,out_v,out_w,count,capacity,local_u[i],local_v[i],local_w[i])
    if count < 0
      return 0
    i += 1
  count

-> ffmdab_part(local_u, local_v, local_w, count, source, axis, width, nonce) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  factor = ffmh_axis_get(local_u,local_v,local_w,source,axis) ## i64
  mask = (1 << width) - 1 ## i64
  donor = (source+1+nonce) % count ## i64
  if donor == source
    donor = (donor+1) % count
  # Reusing another local factor deliberately opens a setup door.  The
  # deterministic mask fallback covers windows whose donor is identical.
  candidate = ffmh_axis_get(local_u,local_v,local_w,donor,axis) ## i64
  if candidate == factor
    candidate = ((nonce*37+source*11+axis*5) & mask)
  if candidate == 0
    candidate = 1
  attempts = 0 ## i64
  while (candidate == 0 || candidate == factor) && attempts <= mask
    candidate += 1
    if candidate > mask
      candidate = 1
    attempts += 1
  if candidate == factor
    return 0
  candidate

-> ffmdab_run(label, path, n, m, p, rectangular, windows, setups_per_window, max_depth, node_cap) (String String i64 i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n,m,p)
  state = i64[ffw_state_size(capacity)]
  rank = 0 ## i64
  if rectangular == 0
    rank = ffw_load_scheme_cap(state,path,n,capacity,118001+n,0,1,1,1)
    if rank < 1 || ffw_verify_best_exact(state,n) != 1
      << "MACRO_DOUBLE_ANNIHILATION tensor="+label+" error=load"
      return 0
  if rectangular != 0
    rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,118001+n+m+p,0,1,1,1)
    if rank < 1 || ffr_verify_best_exact(state,n,m,p) != 1
      << "MACRO_DOUBLE_ANNIHILATION tensor="+label+" error=load"
      return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  z = ffw_export_best(state,us,vs,ws) ## i64
  local_count = 4 ## i64
  shape = i64[3]
  shape[0] = n*m
  shape[1] = m*p
  shape[2] = p*n
  limits = i64[3]
  limits[0] = 1
  limits[1] = max_depth
  limits[2] = node_cap
  empty_goals = i64[6]
  shoulder_count = local_count + 2 ## i64
  workspace_u = i64[node_cap*shoulder_count]
  workspace_v = i64[node_cap*shoulder_count]
  workspace_w = i64[node_cap*shoulder_count]
  workspace_parents = i64[node_cap]
  workspace_depths = i64[node_cap]
  workspace_hashes = i64[node_cap]
  workspace_table = i64[ffrep_table_size(node_cap)]
  searches = 0 ## i64
  nodes = 0 ## i64
  codes = 0 ## i64
  legal = 0 ## i64
  revisits = 0 ## i64
  capped = 0 ## i64
  root_ready = 0 ## i64
  goal_states = 0 ## i64
  local_closes = 0 ## i64
  manufactured_closes = 0 ## i64
  full_gates = 0 ## i64
  full_drops = 0 ## i64
  gate_failures = 0 ## i64
  best_depth = 0 ## i64
  started = ccall("__w_clock_ms") ## i64
  window = 0 ## i64
  while window < windows
    selected = i64[local_count]
    z = ffmdab_window(us,vs,ws,rank,window,local_count,selected)
    local_u = i64[local_count]
    local_v = i64[local_count]
    local_w = i64[local_count]
    z = ffmdab_capture(us,vs,ws,selected,local_count,local_u,local_v,local_w)
    proposal = 0 ## i64
    while proposal < setups_per_window
      setup = i64[6]
      setup[0] = (window+proposal) % local_count
      setup[3] = (window+proposal*2+2) % local_count
      if setup[3] == setup[0]
        setup[3] = (setup[3]+1) % local_count
      setup[1] = (window+proposal) % 3
      setup[4] = (window+proposal+1) % 3
      setup[2] = ffmdab_part(local_u,local_v,local_w,local_count,setup[0],setup[1],shape[setup[1]],window*setups_per_window+proposal) ## i64
      setup[5] = ffmdab_part(local_u,local_v,local_w,local_count,setup[3],setup[4],shape[setup[4]],window*setups_per_window+proposal+101)
      if setup[2] > 0 && setup[5] > 0
        searches += 1
        out_u = i64[local_count+2]
        out_v = i64[local_count+2]
        out_w = i64[local_count+2]
        recipe = i64[72]
        stats = i64[20]
        out_count = ffmda_search_workspace(local_u,local_v,local_w,local_count,setup,empty_goals,shape,limits,0,workspace_u,workspace_v,workspace_w,workspace_parents,workspace_depths,workspace_hashes,workspace_table,out_u,out_v,out_w,recipe,stats) ## i64
        nodes += stats[0]
        codes += stats[1]
        legal += stats[2]
        revisits += stats[3]
        capped += stats[4]
        root_ready += stats[17]
        goal_states += stats[6]
        if out_count > 0
          local_closes += 1
          if stats[17] == 0
            manufactured_closes += 1
            if best_depth == 0 || recipe[8] < best_depth
              best_depth = recipe[8]
            candidate_u = i64[capacity]
            candidate_v = i64[capacity]
            candidate_w = i64[capacity]
            candidate_rank = ffmdab_splice(us,vs,ws,rank,selected,local_count,out_u,out_v,out_w,out_count,candidate_u,candidate_v,candidate_w,capacity) ## i64
            if candidate_rank > 0
              child = i64[ffw_state_size(capacity)]
              exact = 0 ## i64
              if rectangular == 0
                loaded = ffw_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,capacity,119001+full_gates,0,1,1,1) ## i64
                if loaded == candidate_rank
                  exact = ffw_verify_best_exact(child,n)
              if rectangular != 0
                loaded = ffr_init_terms_cap(child,candidate_u,candidate_v,candidate_w,candidate_rank,n,m,p,capacity,119001+full_gates,0,1,1,1)
                if loaded == candidate_rank
                  exact = ffr_verify_best_exact(child,n,m,p)
              full_gates += 1
              if exact == 1 && candidate_rank < rank
                full_drops += 1
              if exact != 1
                gate_failures += 1
      proposal += 1
    window += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "MACRO_DOUBLE_ANNIHILATION tensor="+label+" rank="+rank.to_s()+" windows="+windows.to_s()+" setups="+searches.to_s()+" depth=1-"+max_depth.to_s()+" cap="+node_cap.to_s()+" nodes="+nodes.to_s()+" codes="+codes.to_s()+" legal="+legal.to_s()+" revisits="+revisits.to_s()+" capped="+capped.to_s()+" root_ready="+root_ready.to_s()+" goal_states="+goal_states.to_s()+" local_closes="+local_closes.to_s()+" manufactured="+manufactured_closes.to_s()+" full_gates="+full_gates.to_s()+" full_drops="+full_drops.to_s()+" gate_fail="+gate_failures.to_s()+" best_depth="+best_depth.to_s()+" ms="+elapsed.to_s()
  1

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffmdab_run("2x2x5",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5,1,64,6,6,8192) ## i64
z = ffmdab_run("2x2x7",root+"matmul_2x2x7_rank25_catalog_gf2.txt",2,2,7,1,64,6,6,8192)
z = ffmdab_run("2x2x9",root+"matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt",2,2,9,1,64,6,6,8192)
z = ffmdab_run("2x5x6",root+"matmul_2x5x6_rank47_catalog_gf2.txt",2,5,6,1,64,6,6,8192)
z = ffmdab_run("3x4x6",root+"matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt",3,4,6,1,64,6,6,8192)
z = ffmdab_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5,1,64,6,6,8192)
z = ffmdab_run("4x5x6",root+"matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt",4,5,6,1,64,6,6,8192)
z = ffmdab_run("4x5x7",root+"matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt",4,5,7,1,64,6,6,8192)
