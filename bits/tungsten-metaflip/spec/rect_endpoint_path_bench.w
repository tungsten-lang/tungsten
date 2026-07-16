# Bounded decision benchmark for compiling real archive-to-archive rectangular
# fringe changes into ordinary exact flip words. A miss is an experimental
# result, not a test failure; malformed inputs, local-gate failures, or replay
# failures are fatal.

use ../lib/metaflip/strategies/rect_endpoint_path
use ../lib/metaflip/rect

-> ffrepb_fail(label) (String) i64
  << "FAIL rectangular endpoint path bench: " + label
  exit(1)
  0

-> ffrepb_contains(us, vs, ws, count, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < count
    if us[i] == u && vs[i] == v && ws[i] == w
      return 1
    i += 1
  0

-> ffrepb_run(label, left_path, right_path, n, m, p, expected_fringe, max_depth, node_cap) (String String String i64 i64 i64 i64 i64 i64) i64
  rect_mode = ffr_supported(n,m,p) ## i64
  capacity = ffw_default_capacity(n) ## i64
  if rect_mode == 1
    capacity = ffr_default_capacity(n,m,p)
  left = i64[ffw_state_size(capacity)]
  right = i64[ffw_state_size(capacity)]
  left_rank = 0 - 1 ## i64
  right_rank = 0 - 1 ## i64
  left_exact = 0 ## i64
  right_exact = 0 ## i64
  if rect_mode == 1
    left_rank = ffr_load_scheme_cap(left,left_path,n,m,p,capacity,98001,0,1,1,1)
    right_rank = ffr_load_scheme_cap(right,right_path,n,m,p,capacity,98003,0,1,1,1)
    left_exact = ffr_verify_best_exact(left,n,m,p)
    right_exact = ffr_verify_best_exact(right,n,m,p)
  if rect_mode == 0 && n == m && m == p
    left_rank = ffw_load_scheme_cap(left,left_path,n,capacity,98001,0,1,1,1)
    right_rank = ffw_load_scheme_cap(right,right_path,n,capacity,98003,0,1,1,1)
    left_exact = ffw_verify_best_exact(left,n)
    right_exact = ffw_verify_best_exact(right,n)
  if left_rank < 1 || right_rank != left_rank || left_exact != 1 || right_exact != 1
    return ffrepb_fail(label+" certificates ranks="+left_rank.to_s()+"/"+right_rank.to_s()+" exact="+left_exact.to_s()+"/"+right_exact.to_s())
  left_u = i64[capacity]
  left_v = i64[capacity]
  left_w = i64[capacity]
  right_u = i64[capacity]
  right_v = i64[capacity]
  right_w = i64[capacity]
  if ffw_export_best(left,left_u,left_v,left_w) != left_rank || ffw_export_best(right,right_u,right_v,right_w) != right_rank
    return ffrepb_fail(label+" export")

  source_u = i64[ffrep_max_count()]
  source_v = i64[ffrep_max_count()]
  source_w = i64[ffrep_max_count()]
  target_u = i64[ffrep_max_count()]
  target_v = i64[ffrep_max_count()]
  target_w = i64[ffrep_max_count()]
  source_count = 0 ## i64
  target_count = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    if ffrepb_contains(right_u,right_v,right_w,right_rank,left_u[i],left_v[i],left_w[i]) == 0
      if source_count >= ffrep_max_count()
        return ffrepb_fail(label+" source fringe exceeds bound")
      source_u[source_count] = left_u[i]
      source_v[source_count] = left_v[i]
      source_w[source_count] = left_w[i]
      source_count += 1
    i += 1
  i = 0
  while i < right_rank
    if ffrepb_contains(left_u,left_v,left_w,left_rank,right_u[i],right_v[i],right_w[i]) == 0
      if target_count >= ffrep_max_count()
        return ffrepb_fail(label+" target fringe exceeds bound")
      target_u[target_count] = right_u[i]
      target_v[target_count] = right_v[i]
      target_w[target_count] = right_w[i]
      target_count += 1
    i += 1
  if source_count != expected_fringe || target_count != expected_fringe
    return ffrepb_fail(label+" fringe="+source_count.to_s()+"/"+target_count.to_s()+" expected="+expected_fringe.to_s())
  udim = n*m ## i64
  vdim = m*p ## i64
  wdim = n*p ## i64
  if ffrep_local_exact_shape(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim) != 1
    return ffrepb_fail(label+" local exact")

  recipe = i64[ffrep_recipe_size()]
  stats = i64[ffrep_stats_size()]
  start = ccall("__w_clock_ms") ## i64
  found = ffrep_search_same_rank(source_u,source_v,source_w,source_count,target_u,target_v,target_w,target_count,udim,vdim,wdim,max_depth,node_cap,recipe,stats) ## i64
  elapsed = ccall("__w_clock_ms") - start ## i64
  if found > 0 && (stats[11] != 1 || stats[12] != 1 || stats[15] != 1)
    return ffrepb_fail(label+" replay")
  << "RECT_ENDPOINT_PATH_BENCH label="+label+" fringe="+source_count.to_s()+" depth_cap="+max_depth.to_s()+" node_cap="+node_cap.to_s()+" found="+found.to_s()+" forward_states="+stats[0].to_s()+" backward_states="+stats[1].to_s()+" legal="+stats[4].to_s()+" revisits="+stats[5].to_s()+" meets="+stats[6].to_s()+" capped="+stats[10].to_s()+" ms="+elapsed.to_s()
  found

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
z = ffrepb_run("456-d906-v-d907",root+"matmul_4x5x6_rank90_d906_rect_portfolio_gf2.txt",root+"matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt",4,5,6,2,10,4096) ## i64
z = ffrepb_run("666-d2502-v-d2508-s3",root+"matmul_6x6_rank153_d2502_gf2.txt",root+"matmul_6x6_rank153_d2508_d3_partial_nullspace_s3_gf2.txt",6,6,6,4,10,8192)
z = ffrepb_run("666-d2502-v-d2512-s4",root+"matmul_6x6_rank153_d2502_gf2.txt",root+"matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt",6,6,6,6,10,8192)
<< "PASS rect_endpoint_path_bench"
