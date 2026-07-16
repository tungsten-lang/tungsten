# Decision benchmark and independent equivalence oracle for the production
# support-major exact gate.  The local reference deliberately retains the old
# coefficient-major reconstruction so exact and corrupted schemes exercise
# two structurally different algorithms.

use ../lib/metaflip/rect

-> ffpvb_coefficient_error(st, uo, vo, wo, liveo, rank, n, m, p) (i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  uw = n * m ## i64
  vw = m * p ## i64
  ww = n * p ## i64
  ai = 0 ## i64
  while ai < uw
    bi = 0 ## i64
    while bi < vw
      ci = 0 ## i64
      while ci < ww
        got = 0 ## i64
        term = 0 ## i64
        while term < rank
          slot = term ## i64
          if liveo >= 0
            slot = st[liveo+term]
          if ((st[uo+slot] >> ai) & 1) != 0 && ((st[vo+slot] >> bi) & 1) != 0 && ((st[wo+slot] >> ci) & 1) != 0
            got = got ^ 1
          term += 1
        arow = ai / m ## i64
        acol = ai % m ## i64
        brow = bi / p ## i64
        bcol = bi % p ## i64
        crow = ci / p ## i64
        ccol = ci % p ## i64
        want = 0 ## i64
        if acol == brow && arow == crow && bcol == ccol
          want = 1
        if got != want
          return 1 + (ai * vw + bi) * ww + ci
        ci += 1
      bi += 1
    ai += 1
  0

-> ffpvb_run(label, path, n, m, p) (String String i64 i64 i64) i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state,path,n,m,p,capacity,9917,4,4,1000,250) ## i64
  if rank < 1
    << "FAIL load " + label
    return 0
  t0 = ccall_nobox("__w_clock_ns_raw") ## i64
  old_result = ffpvb_coefficient_error(state,state[47],state[48],state[49],0-1,rank,n,m,p) ## i64
  old_ns = ccall_nobox("__w_clock_ns_raw") - t0 ## i64
  t0 = ccall_nobox("__w_clock_ns_raw")
  new_result = ffr_view_error(state,state[47],state[48],state[49],0-1,rank,n,m,p) ## i64
  new_ns = ccall_nobox("__w_clock_ns_raw") - t0 ## i64
  << label + " rank=" + rank.to_s() + " coefficient_ns=" + old_ns.to_s() + " support_ns=" + new_ns.to_s() + " old_result=" + old_result.to_s() + " support_result=" + new_result.to_s()
  if old_result != new_result
    return 0
  original = state[state[47]] ## i64
  changed = original ^ 1 ## i64
  if changed == 0
    changed = original ^ 2
  state[state[47]] = changed
  old_bad = ffpvb_coefficient_error(state,state[47],state[48],state[49],0-1,rank,n,m,p) ## i64
  new_bad = ffr_view_error(state,state[47],state[48],state[49],0-1,rank,n,m,p) ## i64
  state[state[47]] = original
  if old_bad < 1 || old_bad != new_bad
    << "FAIL mismatch oracle " + label + " coefficient=" + old_bad.to_s() + " support=" + new_bad.to_s()
    return 0
  1

-> ffpvb_run_square(label, path, n) (String String i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state,path,n,capacity,11939,4,4,1000,250) ## i64
  if rank < 1
    << "FAIL load " + label
    return 0
  t0 = ccall_nobox("__w_clock_ns_raw") ## i64
  old_result = ffpvb_coefficient_error(state,state[47],state[48],state[49],0-1,rank,n,n,n) ## i64
  old_ns = ccall_nobox("__w_clock_ns_raw") - t0 ## i64
  t0 = ccall_nobox("__w_clock_ns_raw")
  new_result = ffw_verify_view_error(state,state[47],state[48],state[49],0-1,rank,n) ## i64
  new_ns = ccall_nobox("__w_clock_ns_raw") - t0 ## i64
  << label + " rank=" + rank.to_s() + " coefficient_ns=" + old_ns.to_s() + " support_ns=" + new_ns.to_s() + " old_result=" + old_result.to_s() + " support_result=" + new_result.to_s()
  if old_result != new_result
    return 0
  original = state[state[47]] ## i64
  changed = original ^ 1 ## i64
  if changed == 0
    changed = original ^ 2
  state[state[47]] = changed
  old_bad = ffpvb_coefficient_error(state,state[47],state[48],state[49],0-1,rank,n,n,n) ## i64
  new_bad = ffw_verify_view_error(state,state[47],state[48],state[49],0-1,rank,n) ## i64
  state[state[47]] = original
  if old_bad < 1 || old_bad != new_bad
    << "FAIL mismatch oracle " + label + " coefficient=" + old_bad.to_s() + " support=" + new_bad.to_s()
    return 0
  1

root = "lib/metaflip/seeds/gf2/"
ok = 1 ## i64
ok *= ffpvb_run("2x2x5",root+"matmul_2x2x5_rank18_d84_gf2.txt",2,2,5)
ok *= ffpvb_run("4x4x5",root+"matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt",4,4,5)
ok *= ffpvb_run("4x5x7",root+"matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt",4,5,7)
ok *= ffpvb_run_square("5x5",root+"matmul_5x5_rank93_d967_four_split_control_gf2.txt",5)
ok *= ffpvb_run_square("7x7",root+"matmul_7x7_rank247_d3098_affine_code_gf2.txt",7)

if ok == 0
  exit(1)
