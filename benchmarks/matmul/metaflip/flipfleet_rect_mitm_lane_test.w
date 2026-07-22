use flipfleet_rect_mitm_lane_lib

failures = 0 ## i64

-> ffrmt_check(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

failures += ffrmt_check("234 plan", ffrm_plan_valid(2, 3, 4, 4, 180, 2, 0))
failures += ffrmt_check("245 plan", ffrm_plan_valid(2, 4, 5, 4, 180, 2, 0))
failures += ffrmt_check("256 plan", ffrm_plan_valid(2, 5, 6, 16, 384, 8, 64))
failures += ffrmt_check("unsupported shape", ffrm_plan_valid(2, 2, 2, 4, 180, 2, 0) == 0)
failures += ffrmt_check("reject pool", ffrm_plan_valid(2, 3, 4, 4, 701, 2, 0) == 0)

# The square wrapper and generic shape path must remain byte-identical.
square_words = i64[4]
shape_words = i64[4]
z = ffm_fingerprint(3, 5, 9, 9, square_words) ## i64
z = ffm_fingerprint_shape(3, 5, 9, 9, 9, 9, shape_words) ## i64
i = 0 ## i64
while i < 4
  failures += ffrmt_check("square fingerprint word " + i.to_s(), square_words[i] == shape_words[i])
  i += 1

state = ffrm_load_exact(ffrp_seed_rel(2, 3, 4), 2, 3, 4)
failures += ffrmt_check("234 record loads", state != nil)
if state != nil
  cap = ffr_default_capacity(2, 3, 4) ## i64
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  rank = ffw_export_best(state, us, vs, ws) ## i64
  failures += ffrmt_check("234 record rank", rank == 20)

  # Plant a one-term split, then present the two children plus three unchanged
  # terms as a five-term window. The known four-term replacement must pass the
  # rectangular local gate and the independent complete-tensor reconstruction.
  source = 0 - 1 ## i64
  i = 0
  while i < rank && source < 0
    if ffw_popcount(us[i]) > 1
      source = i
    i += 1
  failures += ffrmt_check("splittable source", source >= 0)
  if source >= 0
    pu = i64[cap]
    pv = i64[cap]
    pw = i64[cap]
    bit = us[source] & (0 - us[source]) ## i64
    pu[0] = bit
    pv[0] = vs[source]
    pw[0] = ws[source]
    pu[1] = us[source] ^ bit
    pv[1] = vs[source]
    pw[1] = ws[source]
    pr = 2 ## i64
    i = 0
    while i < rank
      if i != source
        pu[pr] = us[i]
        pv[pr] = vs[i]
        pw[pr] = ws[i]
        pr += 1
      i += 1
    failures += ffrmt_check("planted rank", pr == 21)
    selected = i64[5]
    selected[0] = 0
    selected[1] = 1
    selected[2] = 2
    selected[3] = 3
    selected[4] = 4
    cu = i64[4]
    cv = i64[4]
    cw = i64[4]
    cu[0] = us[source]
    cv[0] = vs[source]
    cw[0] = ws[source]
    j = 1 ## i64
    while j < 4
      cu[j] = pu[j + 1]
      cv[j] = pv[j + 1]
      cw[j] = pw[j + 1]
      j += 1
    indices = i64[4]
    indices[0] = 0
    indices[1] = 1
    indices[2] = 2
    indices[3] = 3
    failures += ffrmt_check("rectangular local identity", ffm_local_exact_shape(pu, pv, pw, selected, cu, cv, cw, indices, 6, 12, 8))
    saved = cu[0] ## i64
    cu[0] = cu[1]
    failures += ffrmt_check("rectangular local reject", ffm_local_exact_shape(pu, pv, pw, selected, cu, cv, cw, indices, 6, 12, 8) == 0)
    cu[0] = saved
    output = "/tmp/flipfleet_rect_mitm_lane_test_hit.txt"
    output_rank = ffrm_accept_and_dump(pu, pv, pw, pr, selected, cu, cv, cw, indices, 2, 3, 4, output) ## i64
    failures += ffrmt_check("full rectangular reconstruction", output_rank == 20)
    reloaded = ffrm_load_exact(output, 2, 3, 4)
    failures += ffrmt_check("written rectangular scheme exact", reloaded != nil && ffr_best_rank(reloaded) == 20)

failures += ffrmt_check("refuse seed overwrite", ffrm_search(ffrp_seed_rel(2, 3, 4), ffrp_seed_rel(2, 3, 4), 2, 3, 4, 1, 4, 0, 0, "unused.metal") == 0 - 3)

# End-to-end Metal control. The checked-in rank-21 shoulder splits the first
# U factor of the rank-20 frontier into 8 and 16. Its first five terms therefore
# have a known four-term replacement in the bounded factor-XOR candidate pool.
gpu_seed = "benchmarks/matmul/metaflip/mitm_planted_2x3x4_rank21_gf2.txt"
gpu_state = ffrm_load_exact(gpu_seed, 2, 3, 4)
failures += ffrmt_check("planted GPU shoulder exact", gpu_state != nil && ffr_best_rank(gpu_state) == 21)
gpu_selected = i64[5]
gpu_selected[0] = 0
gpu_selected[1] = 1
gpu_selected[2] = 2
gpu_selected[3] = 3
gpu_selected[4] = 4
gpu_cap = ffr_default_capacity(2, 3, 4) ## i64
gpu_us = i64[gpu_cap]
gpu_vs = i64[gpu_cap]
gpu_ws = i64[gpu_cap]
gpu_rank = ffw_export_best(gpu_state, gpu_us, gpu_vs, gpu_ws) ## i64
gpu_cu = i64[256]
gpu_cv = i64[256]
gpu_cw = i64[256]
gpu_count = ffm_candidates(gpu_us, gpu_vs, gpu_ws, gpu_rank, gpu_selected, 256, 2, gpu_cu, gpu_cv, gpu_cw) ## i64
gpu_replacement = i64[4]
gpu_replacement[0] = 0 - 1
gpu_replacement[1] = 0 - 1
gpu_replacement[2] = 0 - 1
gpu_replacement[3] = 0 - 1
gpu_i = 0 ## i64
while gpu_i < gpu_count
  if gpu_cu[gpu_i] == 24 && gpu_cv[gpu_i] == 272 && gpu_cw[gpu_i] == 17
    gpu_replacement[0] = gpu_i
  if gpu_cu[gpu_i] == gpu_us[2] && gpu_cv[gpu_i] == gpu_vs[2] && gpu_cw[gpu_i] == gpu_ws[2]
    gpu_replacement[1] = gpu_i
  if gpu_cu[gpu_i] == gpu_us[3] && gpu_cv[gpu_i] == gpu_vs[3] && gpu_cw[gpu_i] == gpu_ws[3]
    gpu_replacement[2] = gpu_i
  if gpu_cu[gpu_i] == gpu_us[4] && gpu_cv[gpu_i] == gpu_vs[4] && gpu_cw[gpu_i] == gpu_ws[4]
    gpu_replacement[3] = gpu_i
  gpu_i += 1
if gpu_replacement[0] < 0 || gpu_replacement[1] < 0 || gpu_replacement[2] < 0 || gpu_replacement[3] < 0
  << "FAIL planted replacement absent from candidate pool"
  failures += 1
else
  if ffm_local_exact_shape(gpu_us, gpu_vs, gpu_ws, gpu_selected, gpu_cu, gpu_cv, gpu_cw, gpu_replacement, 6, 12, 8) != 1
    << "FAIL planted replacement not locally exact"
    failures += 1
gpu_output = "/tmp/flipfleet_rect_mitm_lane_gpu_hit.txt"
gpu_hit = ffrm_search_exact_subset(gpu_seed, gpu_output, 2, 3, 4, 256, 2, gpu_selected, "benchmarks/matmul/metaflip/flipfleet_rect_mitm_lane_test.metal") ## i64
if gpu_hit != 1
  << "FAIL planted GPU collision recovery"
  failures += 1
gpu_reloaded = ffrm_load_exact(gpu_output, 2, 3, 4)
if gpu_reloaded == nil
  << "FAIL planted GPU output missing"
  failures += 1
else
  if ffr_best_rank(gpu_reloaded) != 20 || ffr_verify_best_exact(gpu_reloaded, 2, 3, 4) != 1
    << "FAIL planted GPU output exact"
    failures += 1

if failures > 0
  << "flipfleet_rect_mitm_lane_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_rect_mitm_lane_test: all checks passed"
