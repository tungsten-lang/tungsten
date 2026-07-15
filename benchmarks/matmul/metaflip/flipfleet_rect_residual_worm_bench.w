# Bounded <2,2,5> residual-worm experiment with an equal-proposal ordinary
# FlipFleet control.  No production profile is changed by this benchmark.

use flipfleet_rect_residual_worm

-> ffrrwb_fail(message)
  << "RESIDUAL_WORM_FAIL " + message
  exit(1)
  0

-> ffrrwb_dump(path, us, vs, ws, rank) (String i64[] i64[] i64[] i64) i64
  body = rank.to_s() + "\n"
  i = 0 ## i64
  while i < rank
    body = body + us[i].to_s() + " " + vs[i].to_s() + " " + ws[i].to_s() + "\n"
    i += 1
  if write_file(path, body)
    return rank
  0

# stats: minimum/maximum/sum deletion syndrome, unit deletions.
-> ffrrwb_deletion_stats(us, vs, ws, rank, stats) (i64[] i64[] i64[] i64 i64[]) i64
  stats[0] = 9223372036854775807
  stats[1] = 0
  stats[2] = 0
  stats[3] = 0
  i = 0 ## i64
  while i < rank
    weight = ffw_popcount(us[i]) * ffw_popcount(vs[i]) * ffw_popcount(ws[i]) ## i64
    if weight < stats[0]
      stats[0] = weight
    if weight > stats[1]
      stats[1] = weight
    stats[2] += weight
    if weight == 1
      stats[3] += 1
    i += 1
  rank

-> ffrrwb_load(path, seed, us, vs, ws) (String i64 i64[] i64[] i64[]) i64
  n = 2 ## i64
  m = 2 ## i64
  p = 5 ## i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_load_scheme_cap(state, path, n, m, p, capacity, seed, 4, 8, 1000, 250) ## i64
  if rank != 18 || ffr_verify_current_exact(state, n, m, p) != 1
    return 0
  ffw_export_current(state, us, vs, ws)

-> ffrrwb_ordinary(path, attempts, seed, label) (String i64 i64 String) i64
  n = 2 ## i64
  m = 2 ## i64
  p = 5 ## i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  loaded = ffr_load_scheme_cap(state, path, n, m, p, capacity, seed, 4, 8, ffrp_work_quota(attempts), ffrp_wander_quota(attempts)) ## i64
  if loaded != 18
    ffrrwb_fail("ordinary load " + label)
  initial_bits = ffw_best_bits(state) ## i64
  phases = i64[3]
  z = ffrp_campaign_budgets(attempts, phases) ## i64
  t0 = ccall("__w_clock_ms") ## i64
  rank = ffr_work(state, phases[0]) ## i64
  rank = ffr_walk(state, phases[1])
  rank = ffr_wander(state, phases[2])
  elapsed = ccall("__w_clock_ms") - t0 ## i64
  exact = ffr_verify_best_exact(state, n, m, p) ## i64
  << "RESIDUAL_WORM_CONTROL door=" + label + " attempts=" + attempts.to_s() + " moves=" + ffw_moves(state).to_s() + " start_rank=18 best_rank=" + rank.to_s() + " start_density=" + initial_bits.to_s() + " best_density=" + ffw_best_bits(state).to_s() + " exact=" + exact.to_s() + " elapsed_ms=" + elapsed.to_s()
  rank

-> ffrrwb_run(path, attempts, seed, label) (String i64 i64 String) i64
  source_u = i64[18]
  source_v = i64[18]
  source_w = i64[18]
  if ffrrwb_load(path, seed, source_u, source_v, source_w) != 18
    ffrrwb_fail("source load " + label)
  deletion = i64[4]
  z = ffrrwb_deletion_stats(source_u, source_v, source_w, 18, deletion) ## i64
  out_u = i64[17]
  out_v = i64[17]
  out_w = i64[17]
  meta = i64[25]
  t0 = ccall("__w_clock_ms") ## i64
  weight = ffrrw_search_rank_minus_one(source_u, source_v, source_w, 18, 2, 2, 5, attempts, seed + 700001, out_u, out_v, out_w, meta) ## i64
  elapsed = ccall("__w_clock_ms") - t0 ## i64
  if weight < 0
    ffrrwb_fail("worm invariant " + label + " code=" + weight.to_s())
  best_path = "/tmp/flipfleet_2x2x5_rank17_" + label + "_residual_w" + weight.to_s() + ".txt"
  if ffrrwb_dump(best_path, out_u, out_v, out_w, 17) != 17
    ffrrwb_fail("dump " + label)
  target = i64[ffrrw_tensor_words(2, 2, 5)]
  carrier = i64[target.size()]
  z = ffrrw_build_mmt_target(target, 2, 2, 5)
  rebuilt = ffrrw_build_residual(out_u, out_v, out_w, 17, 2, 2, 5, target, carrier) ## i64
  if rebuilt != weight
    ffrrwb_fail("final residual replay " + label)
  << "RESIDUAL_WORM_RESULT door=" + label + " attempts=" + meta[0].to_s() + " restarts=" + meta[1].to_s() + " deletion_weight_min=" + deletion[0].to_s() + " deletion_weight_max=" + deletion[1].to_s() + " deletion_weight_mean_milli=" + (deletion[2] * 1000 / 18).to_s() + " unit_deletions=" + deletion[3].to_s() + " best_weight=" + weight.to_s() + " starts_improved=" + meta[4].to_s() + " accepted=" + meta[5].to_s() + " strict_improvements=" + meta[6].to_s() + " forced_tunnels=" + meta[7].to_s() + " floor_moves=" + meta[8].to_s() + " distinct_floor_cells=" + meta[9].to_s() + " floor_config_coverage_sum=" + meta[24].to_s() + " consistency_checks=" + meta[10].to_s() + " exact_hit=" + meta[11].to_s() + " best_proxy=" + meta[12].to_s() + " flatten_ranks=" + meta[13].to_s() + "/" + meta[14].to_s() + "/" + meta[15].to_s() + " max_carrier=" + meta[16].to_s() + " best_drop=" + meta[17].to_s() + " independent_gate=" + meta[18].to_s() + " uphill_accepts=" + meta[20].to_s() + " neutral_accepts=" + meta[21].to_s() + " best_resets=" + meta[22].to_s() + " directed_floor_attempts=" + meta[23].to_s() + " elapsed_ms=" + elapsed.to_s() + " path=" + best_path
  ordinary_rank = ffrrwb_ordinary(path, attempts, seed + 900001, label) ## i64
  if weight == 0
    return 1
  0

av = argv()
attempts = 180000 ## i64
if av.size() > 1
  << "usage: residual-worm-bench [attempts-per-door]"
  exit(2)
if av.size() == 1
  attempts = av[0].to_i()
if attempts < 180
  << "attempts-per-door must be at least 180"
  exit(2)

root = "benchmarks/matmul/metaflip/"
hit84 = ffrrwb_run(root + "matmul_2x2x5_rank18_d84_gf2.txt", attempts, 2258401, "d84") ## i64
hit88 = ffrrwb_run(root + "matmul_2x2x5_rank18_d88_gf2.txt", attempts, 2258801, "d88") ## i64
<< "RESIDUAL_WORM_SUMMARY attempts_per_door=" + attempts.to_s() + " total_worm_attempts=" + (attempts * 2).to_s() + " total_control_moves=" + (attempts * 2).to_s() + " exact_hits=" + (hit84 + hit88).to_s()
