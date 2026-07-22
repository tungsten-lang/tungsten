# Exact-gated decision benchmark for the one-lane rectangular split cadence.
# Screening compares the retained current endpoint and a fresh ordinary
# continuation, never raw proposal/acceptance throughput.
#
#   rect_split_cadence_fertility_bench [moves] [trials]
#                                        [continuation-moves] [shape|all]

use ../lib/metaflip/rect
use ../lib/metaflip/rect/cpu_pool

-> rscfb_better(ar, ab, br, bb) (i64 i64 i64 i64) i64
  if ar < br
    return 1
  if ar == br && ab < bb
    return 1
  0

-> rscfb_source_distance(st, us, vs, ws, rank) (i64[] i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffw_find_term(st, us[i], vs[i], ws[i]) >= 0
      common += 1
    i += 1
  rank + ffr_current_rank(st) - common - common

-> rscfb_run_phase(st, moves, cadence) (i64[] i64 i64) i64
  phase = i64[3]
  z = ffrp_campaign_budgets(moves, phase) ## i64
  result = 0 ## i64
  if cadence == 2000
    result = ffr_work(st, phase[0])
    result = ffr_walk(st, phase[1])
    result = ffr_wander(st, phase[2])
  if cadence != 2000
    result = ffrcp_work_cadence(st, phase[0], cadence)
    result = ffrcp_walk_cadence(st, phase[1], cadence)
    result = ffrcp_wander_cadence(st, phase[2], cadence)
  result

# stats per arm: runs, current exact, best exact, source wins, best rank sum,
# best bits sum, current rank sum, current bits sum, source-distance sum,
# continuation source wins, continuation rank sum, continuation bits sum.
-> rscfb_report(label, moves, trials, continuation, stats, pair_wins) (String i64 i64 i64 i64[] i64[]) i64
  width = 12 ## i64
  body = StringBuffer(2048) ## reuse
  body << "RECT_SPLIT_CADENCE tensor=" << label << " moves=" << moves
  body << " trials=" << trials << " continuation=" << continuation << "\n"
  arm = 0 ## i64
  while arm < 2
    off = arm * width ## i64
    name = "cadence-2000" ## String
    if arm == 1
      name = "cadence-8000"
    body << "RECT_SPLIT_CADENCE arm=" << name << " runs=" << stats[off]
    body << " exact=" << stats[off + 1] << "/" << stats[off + 2]
    body << " source_wins=" << stats[off + 3]
    body << " best_sum=" << stats[off + 4] << "/" << stats[off + 5]
    body << " current_sum=" << stats[off + 6] << "/" << stats[off + 7]
    body << " distance_sum=" << stats[off + 8]
    body << " cont_source_wins=" << stats[off + 9]
    body << " cont_sum=" << stats[off + 10] << "/" << stats[off + 11] << "\n"
    arm += 1
  body << "RECT_SPLIT_CADENCE paired candidate/base/tie="
  body << pair_wins[0] << "/" << pair_wins[1] << "/" << pair_wins[2] << "\n"
  rendered = body.to_s() ## String
  << rendered
  flush()
  1

-> rscfb_shape(label, path, n, m, p, source_rank, moves, trials, continuation) (String String i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  state_size = ffr_state_size(capacity) ## i64
  width = 12 ## i64
  stats = i64[width * 2]
  pair_wins = i64[3]
  trial = 0 ## i64
  while trial < trials
    seed = 730001 + n * 1009 + m * 9176 + p * 65537 + trial * 104729 ## i64
    source = i64[state_size]
    loaded = ffr_load_scheme_cap(source, path, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
    if loaded != source_rank || ffr_verify_best_exact(source, n, m, p) != 1
      << "RECT_SPLIT_CADENCE_FAIL tensor=" + label + " stage=load"
      exit(1)
    source_bits = ffr_best_bits(source) ## i64
    source_u = i64[capacity]
    source_v = i64[capacity]
    source_w = i64[capacity]
    exported = ffw_export_best(source, source_u, source_v, source_w) ## i64
    baseline_rank = 0 ## i64
    baseline_bits = 0 ## i64
    arm = 0 ## i64
    while arm < 2
      cadence = 2000 ## i64
      if arm == 1
        cadence = 8000
      st = i64[state_size]
      cloned = ffr_init_terms_cap(st, source_u, source_v, source_w, exported, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
      if cloned != source_rank
        << "RECT_SPLIT_CADENCE_FAIL tensor=" + label + " stage=clone"
        exit(1)
      z = rscfb_run_phase(st, moves, cadence) ## i64
      current_exact = ffr_verify_current_exact(st, n, m, p) ## i64
      best_exact = ffr_verify_best_exact(st, n, m, p) ## i64
      if current_exact != 1 || best_exact != 1
        << "RECT_SPLIT_CADENCE_FAIL tensor=" + label + " stage=search-exact"
        exit(1)
      off = arm * width ## i64
      best_rank = ffr_best_rank(st) ## i64
      best_bits = ffr_best_bits(st) ## i64
      stats[off] += 1
      stats[off + 1] += current_exact
      stats[off + 2] += best_exact
      if rscfb_better(best_rank, best_bits, source_rank, source_bits) != 0
        stats[off + 3] += 1
      stats[off + 4] += best_rank
      stats[off + 5] += best_bits
      stats[off + 6] += ffr_current_rank(st)
      stats[off + 7] += ffr_current_bits(st)
      stats[off + 8] += rscfb_source_distance(st, source_u, source_v, source_w, source_rank)

      endpoint_u = i64[capacity]
      endpoint_v = i64[capacity]
      endpoint_w = i64[capacity]
      endpoint_rank = ffw_export_current(st, endpoint_u, endpoint_v, endpoint_w) ## i64
      child = i64[state_size]
      continuation_seed = 970001 + trial * 15485863 ## i64
      child_rank = ffr_init_terms_cap(child, endpoint_u, endpoint_v, endpoint_w, endpoint_rank, n, m, p, capacity, continuation_seed, 6, 4, 1000000000, 200000000) ## i64
      if child_rank != endpoint_rank
        << "RECT_SPLIT_CADENCE_FAIL tensor=" + label + " stage=continuation-clone"
        exit(1)
      z = ffr_walk(child, continuation)
      if ffr_verify_current_exact(child, n, m, p) != 1 || ffr_verify_best_exact(child, n, m, p) != 1
        << "RECT_SPLIT_CADENCE_FAIL tensor=" + label + " stage=continuation-exact"
        exit(1)
      continuation_rank = ffr_best_rank(child) ## i64
      continuation_bits = ffr_best_bits(child) ## i64
      if rscfb_better(continuation_rank, continuation_bits, source_rank, source_bits) != 0
        stats[off + 9] += 1
      stats[off + 10] += continuation_rank
      stats[off + 11] += continuation_bits
      if arm == 0
        baseline_rank = continuation_rank
        baseline_bits = continuation_bits
      if arm == 1
        if rscfb_better(continuation_rank, continuation_bits, baseline_rank, baseline_bits) != 0
          pair_wins[0] += 1
        if rscfb_better(baseline_rank, baseline_bits, continuation_rank, continuation_bits) != 0
          pair_wins[1] += 1
        if continuation_rank == baseline_rank && continuation_bits == baseline_bits
          pair_wins[2] += 1
      arm += 1
    trial += 1
  rscfb_report(label, moves, trials, continuation, stats, pair_wins)

args = argv()
moves = 2000000 ## i64
trials = 8 ## i64
continuation = 1000000 ## i64
shape = "all" ## String
if args.size() > 0
  moves = args[0].to_i()
if args.size() > 1
  trials = args[1].to_i()
if args.size() > 2
  continuation = args[2].to_i()
if args.size() > 3
  shape = args[3]
if moves < 1000
  moves = 1000
if trials < 1
  trials = 1
if continuation < 1
  continuation = 1
root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String

if shape == "all" || shape == "3x3x4"
  z = rscfb_shape("3x3x4", root + "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, 29, moves, trials, continuation) ## i64
if shape == "all" || shape == "3x4x4"
  z = rscfb_shape("3x4x4", root + "matmul_3x4x4_rank38_d280_live_density_leader_gf2.txt", 3, 4, 4, 38, moves, trials, continuation) ## i64
if shape == "all" || shape == "2x2x5"
  z = rscfb_shape("2x2x5", root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 18, moves, trials, continuation) ## i64
if shape == "all" || shape == "2x2x9"
  z = rscfb_shape("2x2x9", root + "matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt", 2, 2, 9, 32, moves, trials, continuation) ## i64
if shape == "all" || shape == "2x5x6"
  z = rscfb_shape("2x5x6", root + "matmul_2x5x6_rank47_d438_orbit_door_gf2.txt", 2, 5, 6, 47, moves, trials, continuation) ## i64
if shape == "all" || shape == "4x4x5"
  z = rscfb_shape("4x4x5", root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 60, moves, trials, continuation) ## i64
if shape == "all" || shape == "4x5x7"
  z = rscfb_shape("4x5x7", root + "matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt", 4, 5, 7, 104, moves, trials, continuation) ## i64
if shape == "2x2x9-expanded"
  z = rscfb_shape("2x2x9-base", root + "matmul_2x2x9_rank32_d156_perminov_2025_gf2.txt", 2, 2, 9, 32, moves, trials, continuation) ## i64
  z = rscfb_shape("2x2x9-reverse", root + "matmul_2x2x9_rank32_d156_perminov_2025_pperm_reverse_gf2.txt", 2, 2, 9, 32, moves, trials, continuation)
  z = rscfb_shape("2x2x9-cycle", root + "matmul_2x2x9_rank32_d156_perminov_2025_pperm_cycle_gf2.txt", 2, 2, 9, 32, moves, trials, continuation)
  z = rscfb_shape("2x2x9-plus1", root + "matmul_2x2x9_rank33_d159_isotropy_split_plus1_gf2.txt", 2, 2, 9, 33, moves, trials, continuation)
  z = rscfb_shape("2x2x9-plus2", root + "matmul_2x2x9_rank34_d165_isotropy_split_plus2_gf2.txt", 2, 2, 9, 34, moves, trials, continuation)

<< "PASS rectangular split-cadence fertility audit"
