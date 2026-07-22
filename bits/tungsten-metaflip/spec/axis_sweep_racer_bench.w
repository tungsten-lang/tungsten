# Matched-wall-time decision benchmark for the opt-in axis-sweep CPU racer.
#
#   axis_sweep_racer_bench [milliseconds-per-arm] [trials]
#
# Each paired trial loads the same exact record with the same RNG seed.  Arm
# order alternates to reduce thermal/order bias.  Timed work contains only
# ordinary flip proposals (the same 3-work/2-wander mode mix in both arms);
# exactness, endpoint distance, and uniqueness are measured after the clock.

use ../lib/metaflip/rect

-> asrb_contains(values, value) i64
  i = 0 ## i64
  while i < values.size()
    if values[i] == value
      return 1
    i += 1
  0

-> asrb_endpoint_id(st) (i64[]) i64
  digest = 0 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    digest = digest ^ ffw_term_zobrist(st[st[44] + slot], st[st[45] + slot], st[st[46] + slot])
    i += 1
  (digest ^ (st[6] * 6364136223846793005)) & 9223372036854775807

-> asrb_source_distance(st, source_u, source_v, source_w, source_rank) (i64[] i64[] i64[] i64[] i64) i64
  missing = 0 ## i64
  i = 0 ## i64
  while i < source_rank
    if ffw_find_term(st, source_u[i], source_v[i], source_w[i]) < 0
      missing += 1
    i += 1
  extra = 0 ## i64
  i = 0
  while i < st[6]
    slot = st[st[50] + i] ## i64
    found = 0 ## i64
    j = 0 ## i64
    while j < source_rank && found == 0
      if st[st[44] + slot] == source_u[j]
        if st[st[45] + slot] == source_v[j]
          if st[st[46] + slot] == source_w[j]
            found = 1
      j += 1
    if found == 0
      extra += 1
    i += 1
  missing + extra

# stats: elapsed_ns, calls, proposals, legal, accepted, rejected, misses,
# updates, rank_drop, density_gain, current_bits, distance, endpoint_id, exact.
-> asrb_run(path, n, m, p, expected_rank, seed, duration_ns, sweep, stats) (String i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  if n != m || n != p
    capacity = ffr_default_capacity(n, m, p)
  st = i64[ffw_state_size(capacity)]
  loaded = 0 - 1 ## i64
  if n == m && n == p
    loaded = ffw_load_scheme_cap(st, path, n, capacity, seed, 6, 4, 1000000000, 200000000)
  if n != m || n != p
    loaded = ffr_load_scheme_cap(st, path, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000)
  best_exact = 0 ## i64
  if n == m && n == p
    best_exact = ffw_verify_best_exact(st, n)
  if n != m || n != p
    best_exact = ffr_verify_best_exact(st, n, m, p)
  if loaded != expected_rank || best_exact != 1
    return 0
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  source_rank = ffw_export_best(st, source_u, source_v, source_w) ## i64
  source_bits = ffw_best_bits(st) ## i64
  started = ccall_nobox("__w_clock_ns_raw") ## i64
  elapsed = 0 ## i64
  calls = 0 ## i64
  while elapsed < duration_ns
    batch = 0 ## i64
    while batch < 4096
      mode = 0 ## i64
      if (calls % 5) >= 3
        mode = 1
      if sweep == 0
        z = ffw_try_flip(st, mode) ## i64
      if sweep != 0
        z = ffw_try_flip_axis_sweep(st, mode) ## i64
      calls += 1
      batch += 1
    elapsed = ccall_nobox("__w_clock_ns_raw") - started
  exact = 0 ## i64
  if n == m && n == p
    exact = ffw_verify_current_exact(st, n)
    best_exact = ffw_verify_best_exact(st, n)
  if n != m || n != p
    exact = ffr_verify_current_exact(st, n, m, p)
    best_exact = ffr_verify_best_exact(st, n, m, p)
  if best_exact != 1
    exact = 0
  proposals = ffw_proposals(st) ## i64
  misses = ffw_partner_misses(st) ## i64
  legal = proposals - misses ## i64
  rank_drop = expected_rank - ffw_best_rank(st) ## i64
  if rank_drop < 0
    rank_drop = 0
  density_gain = 0 ## i64
  if ffw_best_rank(st) == expected_rank && ffw_best_bits(st) < source_bits
    density_gain = source_bits - ffw_best_bits(st)
  stats[0] = elapsed
  stats[1] = calls
  stats[2] = proposals
  stats[3] = legal
  stats[4] = ffw_accepted(st)
  stats[5] = ffw_rejected(st)
  stats[6] = misses
  stats[7] = ffw_best_updates(st)
  stats[8] = rank_drop
  stats[9] = density_gain
  stats[10] = ffw_current_bits(st)
  stats[11] = asrb_source_distance(st, source_u, source_v, source_w, source_rank)
  stats[12] = asrb_endpoint_id(st)
  stats[13] = exact
  1

-> asrb_report(label, totals, unique_count, trials) (String i64[] i64 i64) i64
  elapsed = totals[0] ## i64
  if elapsed < 1
    elapsed = 1
  legal = totals[3] ## i64
  if legal < 1
    legal = 1
  calls_per_s = totals[1] * 1000000000 / elapsed ## i64
  legal_per_s = totals[3] * 1000000000 / elapsed ## i64
  accepted_per_s = totals[4] * 1000000000 / elapsed ## i64
  legal_ppm = totals[3] * 1000000 / totals[2] ## i64
  accepted_legal_ppm = totals[4] * 1000000 / legal ## i64
  line = "AXIS_SWEEP arm=" + label ## String
  line = line + " trials=" + trials.to_s() + " wall_ns=" + totals[0].to_s()
  line = line + " calls_per_s=" + calls_per_s.to_s() + " legal_per_s=" + legal_per_s.to_s() + " accepted_per_s=" + accepted_per_s.to_s()
  line = line + " proposals=" + totals[2].to_s() + " legal=" + totals[3].to_s() + " legal_ppm=" + legal_ppm.to_s()
  line = line + " accepted=" + totals[4].to_s() + " accepted_legal_ppm=" + accepted_legal_ppm.to_s() + " rejected=" + totals[5].to_s() + " misses=" + totals[6].to_s()
  line = line + " updates=" + totals[7].to_s() + " rank_drop=" + totals[8].to_s() + " density_gain=" + totals[9].to_s()
  line = line + " mean_current_bits=" + (totals[10] / trials).to_s() + " mean_distance=" + (totals[11] / trials).to_s()
  line = line + " unique=" + unique_count.to_s() + " exact=" + totals[13].to_s()
  << line
  1

-> asrb_shape(label, path, n, m, p, expected_rank, duration_ns, trials) (String String i64 i64 i64 i64 i64 i64) i64
  base_totals = i64[14]
  sweep_totals = i64[14]
  base_ids = []
  sweep_ids = []
  sweep_legal_wins = 0 ## i64
  sweep_accept_wins = 0 ## i64
  sweep_density_wins = 0 ## i64
  different_endpoints = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    base_stats = i64[14]
    sweep_stats = i64[14]
    seed = 81001 + n * 1009 + trial * 7919 ## i64
    ok_base = 0 ## i64
    ok_sweep = 0 ## i64
    if (trial % 2) == 0
      ok_base = asrb_run(path, n, m, p, expected_rank, seed, duration_ns, 0, base_stats)
      ok_sweep = asrb_run(path, n, m, p, expected_rank, seed, duration_ns, 1, sweep_stats)
    if (trial % 2) != 0
      ok_sweep = asrb_run(path, n, m, p, expected_rank, seed, duration_ns, 1, sweep_stats)
      ok_base = asrb_run(path, n, m, p, expected_rank, seed, duration_ns, 0, base_stats)
    if ok_base == 0 || ok_sweep == 0 || base_stats[13] != 1 || sweep_stats[13] != 1
      << "FAIL AXIS_SWEEP tensor=" + label + " trial=" + trial.to_s()
      exit(1)
    i = 0 ## i64
    while i < 14
      base_totals[i] = base_totals[i] + base_stats[i]
      sweep_totals[i] = sweep_totals[i] + sweep_stats[i]
      i += 1
    if asrb_contains(base_ids, base_stats[12]) == 0
      base_ids.push(base_stats[12])
    if asrb_contains(sweep_ids, sweep_stats[12]) == 0
      sweep_ids.push(sweep_stats[12])
    if sweep_stats[3] * base_stats[0] > base_stats[3] * sweep_stats[0]
      sweep_legal_wins += 1
    if sweep_stats[4] * base_stats[0] > base_stats[4] * sweep_stats[0]
      sweep_accept_wins += 1
    if sweep_stats[8] > base_stats[8] || (sweep_stats[8] == base_stats[8] && sweep_stats[9] > base_stats[9])
      sweep_density_wins += 1
    if sweep_stats[12] != base_stats[12]
      different_endpoints += 1
    trial += 1
  << "AXIS_SWEEP tensor=" + label + " duration_ns=" + duration_ns.to_s()
  z = asrb_report("baseline", base_totals, base_ids.size(), trials) ## i64
  z = asrb_report("sweep", sweep_totals, sweep_ids.size(), trials)
  base_legal_rate = base_totals[3] * 1000000000 / base_totals[0] ## i64
  sweep_legal_rate = sweep_totals[3] * 1000000000 / sweep_totals[0] ## i64
  base_accept_rate = base_totals[4] * 1000000000 / base_totals[0] ## i64
  sweep_accept_rate = sweep_totals[4] * 1000000000 / sweep_totals[0] ## i64
  legal_delta_ppm = 0 ## i64
  accept_delta_ppm = 0 ## i64
  if base_legal_rate > 0
    legal_delta_ppm = (sweep_legal_rate - base_legal_rate) * 1000000 / base_legal_rate
  if base_accept_rate > 0
    accept_delta_ppm = (sweep_accept_rate - base_accept_rate) * 1000000 / base_accept_rate
  line = "AXIS_SWEEP paired tensor=" + label ## String
  line = line + " legal_delta_ppm=" + legal_delta_ppm.to_s() + " accepted_delta_ppm=" + accept_delta_ppm.to_s()
  line = line + " legal_wins=" + sweep_legal_wins.to_s() + "/" + trials.to_s() + " accept_wins=" + sweep_accept_wins.to_s() + "/" + trials.to_s()
  line = line + " useful_wins=" + sweep_density_wins.to_s() + "/" + trials.to_s() + " different_endpoints=" + different_endpoints.to_s() + "/" + trials.to_s()
  << line
  1

args = argv()
duration_ms = 250 ## i64
trials = 8 ## i64
shape = "all" ## String
if args.size() > 0
  duration_ms = args[0].to_i()
if args.size() > 1
  trials = args[1].to_i()
if args.size() > 2
  shape = args[2]
if duration_ms < 10
  duration_ms = 10
if trials < 1
  trials = 1
duration_ns = duration_ms * 1000000 ## i64
root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String

if shape == "all" || shape == "2x2"
  z = asrb_shape("2x2", root + "matmul_2x2_rank7_d36_gl120_gf2.txt", 2, 2, 2, 7, duration_ns, trials) ## i64
if shape == "all" || shape == "3x3"
  z = asrb_shape("3x3", root + "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, 23, duration_ns, trials) ## i64
if shape == "all" || shape == "4x4"
  z = asrb_shape("4x4", root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 47, duration_ns, trials) ## i64
if shape == "4x4-flips"
  z = asrb_shape("4x4-flips", root + "matmul_4x4_rank47_d677_flips_gf2.txt", 4, 4, 4, 47, duration_ns, trials) ## i64
if shape == "all" || shape == "5x5"
  z = asrb_shape("5x5", root + "matmul_5x5_rank93_d1155_gf2.txt", 5, 5, 5, 93, duration_ns, trials) ## i64
if shape == "all" || shape == "6x6"
  z = asrb_shape("6x6", root + "matmul_6x6_rank153_d1860_global_isotropy_gf2.txt", 6, 6, 6, 153, duration_ns, trials) ## i64
if shape == "all" || shape == "7x7"
  z = asrb_shape("7x7", root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 7, 7, 247, duration_ns, trials) ## i64
if shape == "all" || shape == "2x2x5"
  z = asrb_shape("2x2x5", root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 18, duration_ns, trials) ## i64
<< "PASS axis-sweep matched-wall-time audit"
