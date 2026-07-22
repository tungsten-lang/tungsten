# Matched-wall-time rectangular decision benchmark for the opt-in axis-sweep
# selector.  Screening motion is reported, but production admission is decided
# by exact endpoint diversity and ordinary short-continuation fertility.
#
#   rect_axis_sweep_fertility_bench [milliseconds] [trials] [continuation-steps]
#                                      [4x4x5|4x5x7|2x2x5|all]

use ../lib/metaflip/rect

-> rasfb_expect(label, condition) (String bool) i64
  if !condition
    << "RECT_AXIS_SWEEP_FAIL " + label
    exit(1)
  1

-> rasfb_contains(values, value) i64
  i = 0 ## i64
  while i < values.size()
    if values[i] == value
      return 1
    i += 1
  0

-> rasfb_endpoint_id(st) (i64[]) i64
  digest = 0 ## i64
  sum = 0 ## i64
  i = 0 ## i64
  while i < ffr_current_rank(st)
    slot = st[st[50] + i] ## i64
    term = ffw_term_zobrist(st[st[44] + slot], st[st[45] + slot], st[st[46] + slot]) ## i64
    digest = digest ^ term
    sum = (sum + term) & 9223372036854775807
    i += 1
  (digest ^ (sum >> 1) ^ (ffr_current_rank(st) * 6364136223846793005)) & 9223372036854775807

-> rasfb_current_contains(st, u, v, w) (i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < ffr_current_rank(st)
    slot = st[st[50] + i] ## i64
    if st[st[44] + slot] == u && st[st[45] + slot] == v && st[st[46] + slot] == w
      return 1
    i += 1
  0

-> rasfb_current_distance(left, right) (i64[] i64[]) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < ffr_current_rank(left)
    slot = left[left[50] + i] ## i64
    common += rasfb_current_contains(right, left[left[44] + slot], left[left[45] + slot], left[left[46] + slot])
    i += 1
  ffr_current_rank(left) + ffr_current_rank(right) - common - common

-> rasfb_source_distance(st, us, vs, ws, rank) (i64[] i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < rank
    common += rasfb_current_contains(st, us[i], vs[i], ws[i])
    i += 1
  rank + ffr_current_rank(st) - common - common

# stats: elapsed, calls, proposals, legal, accepted, rejected, misses,
# updates, current rank/bits, best rank/bits, source distance, endpoint id,
# exact current/best, partnerable incidences.
-> rasfb_timed(st, n, m, p, duration_ns, sweep, source_u, source_v, source_w, source_rank, stats) (i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64 i64[]) i64
  before_proposals = ffw_proposals(st) ## i64
  before_accepted = ffw_accepted(st) ## i64
  before_rejected = ffw_rejected(st) ## i64
  before_misses = ffw_partner_misses(st) ## i64
  before_updates = ffw_best_updates(st) ## i64
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
  proposals = ffw_proposals(st) - before_proposals ## i64
  misses = ffw_partner_misses(st) - before_misses ## i64
  stats[0] = elapsed
  stats[1] = calls
  stats[2] = proposals
  stats[3] = proposals - misses
  stats[4] = ffw_accepted(st) - before_accepted
  stats[5] = ffw_rejected(st) - before_rejected
  stats[6] = misses
  stats[7] = ffw_best_updates(st) - before_updates
  stats[8] = ffr_current_rank(st)
  stats[9] = ffr_current_bits(st)
  stats[10] = ffr_best_rank(st)
  stats[11] = ffr_best_bits(st)
  stats[12] = rasfb_source_distance(st, source_u, source_v, source_w, source_rank)
  stats[13] = rasfb_endpoint_id(st)
  stats[14] = ffr_verify_current_exact(st, n, m, p)
  stats[15] = ffr_verify_best_exact(st, n, m, p)
  stats[16] = ffr_partnerable_incidences(st)
  1

# Reinitialize from the exact endpoint to isolate its future fertility from
# proposal-count and RNG differences accumulated during the timed screen.
# stats: runs, exact, rank gains, same-rank density gains, source-record wins,
# sum best rank/bits, best updates, closures to source rank-or-better.
-> rasfb_continue(endpoint, n, m, p, capacity, seed, steps, source_rank, source_bits, stats, result) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[]) i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  endpoint_rank = ffw_export_current(endpoint, us, vs, ws) ## i64
  endpoint_bits = ffr_current_bits(endpoint) ## i64
  child = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(child, us, vs, ws, endpoint_rank, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
  if loaded != endpoint_rank || ffr_verify_best_exact(child, n, m, p) != 1
    return 0
  z = ffr_walk(child, steps) ## i64
  exact = ffr_verify_current_exact(child, n, m, p) * ffr_verify_best_exact(child, n, m, p) ## i64
  best_rank = ffr_best_rank(child) ## i64
  best_bits = ffr_best_bits(child) ## i64
  stats[0] += 1
  stats[1] += exact
  if best_rank < endpoint_rank
    stats[2] += 1
  if best_rank == endpoint_rank && best_bits < endpoint_bits
    stats[3] += 1
  if best_rank < source_rank || (best_rank == source_rank && best_bits < source_bits)
    stats[4] += 1
  stats[5] += best_rank
  stats[6] += best_bits
  stats[7] += ffw_best_updates(child)
  if best_rank <= source_rank
    stats[8] += 1
  result[0] = best_rank
  result[1] = best_bits
  result[2] = endpoint_rank
  result[3] = endpoint_bits
  exact

-> rasfb_report_arm(label, totals, trials, unique, continuations) (String i64[] i64 i64 i64[]) i64
  elapsed = totals[0] ## i64
  legal = totals[3] ## i64
  if elapsed < 1
    elapsed = 1
  if legal < 1
    legal = 1
  line = "RECT_AXIS_SWEEP arm=" + label ## String
  line = line + " trials=" + trials.to_s() + " wall_ns=" + totals[0].to_s()
  line = line + " calls_per_s=" + (totals[1] * 1000000000 / elapsed).to_s()
  line = line + " legal_per_s=" + (totals[3] * 1000000000 / elapsed).to_s()
  line = line + " accepted_per_s=" + (totals[4] * 1000000000 / elapsed).to_s()
  line = line + " legal=" + totals[3].to_s() + " accepted=" + totals[4].to_s() + " rejected=" + totals[5].to_s() + " misses=" + totals[6].to_s()
  line = line + " accept_per_legal_ppm=" + (totals[4] * 1000000 / legal).to_s()
  line = line + " updates=" + totals[7].to_s() + " mean_rank=" + (totals[8] / trials).to_s() + " mean_bits=" + (totals[9] / trials).to_s()
  line = line + " mean_source_distance=" + (totals[12] / trials).to_s() + " unique=" + unique.to_s()
  line = line + " exact=" + totals[14].to_s() + "/" + totals[15].to_s()
  line = line + " mean_partnerable=" + (totals[16] / trials).to_s()
  << line
  c_runs = continuations[0] ## i64
  if c_runs < 1
    c_runs = 1
  cline = "RECT_AXIS_SWEEP continuation arm=" + label ## String
  cline = cline + " runs=" + continuations[0].to_s() + " exact=" + continuations[1].to_s()
  cline = cline + " rank_gains=" + continuations[2].to_s() + " density_gains=" + continuations[3].to_s()
  cline = cline + " source_record_wins=" + continuations[4].to_s() + " closures=" + continuations[8].to_s()
  cline = cline + " mean_best_rank=" + (continuations[5] / c_runs).to_s() + " mean_best_bits=" + (continuations[6] / c_runs).to_s()
  cline = cline + " updates=" + continuations[7].to_s()
  << cline
  1

-> rasfb_shape(label, path, n, m, p, expected_rank, duration_ns, trials, continuation_steps) (String String i64 i64 i64 i64 i64 i64 i64) i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  size = ffr_state_size(capacity) ## i64
  base_totals = i64[17]
  sweep_totals = i64[17]
  base_cont = i64[9]
  sweep_cont = i64[9]
  base_ids = []
  sweep_ids = []
  sweep_legal_wins = 0 ## i64
  sweep_accept_wins = 0 ## i64
  sweep_objective_wins = 0 ## i64
  baseline_endpoint_wins = 0 ## i64
  sweep_endpoint_wins = 0 ## i64
  endpoint_ties = 0 ## i64
  baseline_continuation_wins = 0 ## i64
  sweep_continuation_wins = 0 ## i64
  continuation_ties = 0 ## i64
  cross_distance = 0 ## i64
  source_bits = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 140003 + n * 1009 + m * 9176 + p * 65537 + trial * 7919 ## i64
    baseline = i64[size]
    sweep = i64[size]
    rb = ffr_load_scheme_cap(baseline, path, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
    rs = ffr_load_scheme_cap(sweep, path, n, m, p, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
    z = rasfb_expect(label + " paired load", rb == expected_rank && rs == expected_rank)
    source_u = i64[capacity]
    source_v = i64[capacity]
    source_w = i64[capacity]
    source_count = ffw_export_best(baseline, source_u, source_v, source_w) ## i64
    source_bits = ffr_best_bits(baseline)
    base_stats = i64[17]
    sweep_stats = i64[17]
    if (trial % 2) == 0
      z = rasfb_timed(baseline, n, m, p, duration_ns, 0, source_u, source_v, source_w, source_count, base_stats)
      z = rasfb_timed(sweep, n, m, p, duration_ns, 1, source_u, source_v, source_w, source_count, sweep_stats)
    if (trial % 2) != 0
      z = rasfb_timed(sweep, n, m, p, duration_ns, 1, source_u, source_v, source_w, source_count, sweep_stats)
      z = rasfb_timed(baseline, n, m, p, duration_ns, 0, source_u, source_v, source_w, source_count, base_stats)
    z = rasfb_expect(label + " endpoints exact", base_stats[14] == 1 && base_stats[15] == 1 && sweep_stats[14] == 1 && sweep_stats[15] == 1)
    i = 0 ## i64
    while i < 17
      base_totals[i] += base_stats[i]
      sweep_totals[i] += sweep_stats[i]
      i += 1
    if rasfb_contains(base_ids, base_stats[13]) == 0
      base_ids.push(base_stats[13])
    if rasfb_contains(sweep_ids, sweep_stats[13]) == 0
      sweep_ids.push(sweep_stats[13])
    if sweep_stats[3] * base_stats[0] > base_stats[3] * sweep_stats[0]
      sweep_legal_wins += 1
    if sweep_stats[4] * base_stats[0] > base_stats[4] * sweep_stats[0]
      sweep_accept_wins += 1
    if sweep_stats[10] < base_stats[10] || (sweep_stats[10] == base_stats[10] && sweep_stats[11] < base_stats[11])
      sweep_objective_wins += 1
    if sweep_stats[8] < base_stats[8] || (sweep_stats[8] == base_stats[8] && sweep_stats[9] < base_stats[9])
      sweep_endpoint_wins += 1
    if base_stats[8] < sweep_stats[8] || (base_stats[8] == sweep_stats[8] && base_stats[9] < sweep_stats[9])
      baseline_endpoint_wins += 1
    if base_stats[8] == sweep_stats[8] && base_stats[9] == sweep_stats[9]
      endpoint_ties += 1
    cross_distance += rasfb_current_distance(baseline, sweep)
    rep = 0 ## i64
    while rep < 3
      continuation_seed = 910003 + trial * 104729 + rep * 15485863 ## i64
      base_result = i64[4]
      sweep_result = i64[4]
      z = rasfb_expect(label + " baseline continuation exact", rasfb_continue(baseline, n, m, p, capacity, continuation_seed, continuation_steps, expected_rank, source_bits, base_cont, base_result) == 1)
      z = rasfb_expect(label + " sweep continuation exact", rasfb_continue(sweep, n, m, p, capacity, continuation_seed, continuation_steps, expected_rank, source_bits, sweep_cont, sweep_result) == 1)
      if sweep_result[0] < base_result[0] || (sweep_result[0] == base_result[0] && sweep_result[1] < base_result[1])
        sweep_continuation_wins += 1
      if base_result[0] < sweep_result[0] || (base_result[0] == sweep_result[0] && base_result[1] < sweep_result[1])
        baseline_continuation_wins += 1
      if base_result[0] == sweep_result[0] && base_result[1] == sweep_result[1]
        continuation_ties += 1
      rep += 1
    trial += 1
  << "RECT_AXIS_SWEEP tensor=" + label + " duration_ns=" + duration_ns.to_s() + " continuation_steps=" + continuation_steps.to_s()
  z = rasfb_report_arm("baseline", base_totals, trials, base_ids.size(), base_cont) ## i64
  z = rasfb_report_arm("sweep", sweep_totals, trials, sweep_ids.size(), sweep_cont)
  base_legal_rate = base_totals[3] * 1000000000 / base_totals[0] ## i64
  sweep_legal_rate = sweep_totals[3] * 1000000000 / sweep_totals[0] ## i64
  base_accept_rate = base_totals[4] * 1000000000 / base_totals[0] ## i64
  sweep_accept_rate = sweep_totals[4] * 1000000000 / sweep_totals[0] ## i64
  legal_delta = 0 ## i64
  accept_delta = 0 ## i64
  if base_legal_rate > 0
    legal_delta = (sweep_legal_rate - base_legal_rate) * 1000000 / base_legal_rate
  if base_accept_rate > 0
    accept_delta = (sweep_accept_rate - base_accept_rate) * 1000000 / base_accept_rate
  summary = "RECT_AXIS_SWEEP paired tensor=" + label ## String
  summary = summary + " legal_delta_ppm=" + legal_delta.to_s() + " accepted_delta_ppm=" + accept_delta.to_s()
  summary = summary + " legal_wins=" + sweep_legal_wins.to_s() + "/" + trials.to_s() + " accept_wins=" + sweep_accept_wins.to_s() + "/" + trials.to_s()
  summary = summary + " objective_wins=" + sweep_objective_wins.to_s() + "/" + trials.to_s()
  summary = summary + " endpoint_sweep/base/tie=" + sweep_endpoint_wins.to_s() + "/" + baseline_endpoint_wins.to_s() + "/" + endpoint_ties.to_s()
  summary = summary + " continuation_sweep/base/tie=" + sweep_continuation_wins.to_s() + "/" + baseline_continuation_wins.to_s() + "/" + continuation_ties.to_s()
  summary = summary + " mean_cross_distance=" + (cross_distance / trials).to_s()
  << summary
  1

args = argv()
duration_ms = 300 ## i64
trials = 10 ## i64
continuation_steps = 1000000 ## i64
shape = "all" ## String
if args.size() > 0
  duration_ms = args[0].to_i()
if args.size() > 1
  trials = args[1].to_i()
if args.size() > 2
  continuation_steps = args[2].to_i()
if args.size() > 3
  shape = args[3]
if duration_ms < 10
  duration_ms = 10
if trials < 1
  trials = 1
if continuation_steps < 1
  continuation_steps = 1
duration_ns = duration_ms * 1000000 ## i64
root = __DIR__ + "/../lib/metaflip/seeds/gf2/" ## String

if shape == "all" || shape == "4x4x5"
  z = rasfb_shape("4x4x5", root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", 4, 4, 5, 60, duration_ns, trials, continuation_steps) ## i64
if shape == "all" || shape == "4x5x7"
  z = rasfb_shape("4x5x7", root + "matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt", 4, 5, 7, 104, duration_ns, trials, continuation_steps) ## i64
if shape == "2x2x5"
  z = rasfb_shape("2x2x5", root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 18, duration_ns, trials, continuation_steps) ## i64

<< "PASS rectangular axis-sweep fertility audit"
