# Offline bounded two-term collision-sweep prototype.  The first selected term
# gets the production three-axis sweep.  Only when all three axes miss, one
# fresh uniform *different* live term is sampled and swept before the proposal
# is declared a miss.  Ordinary and production axis-sweep code is untouched.
#
#   two_term_collision_sweep_bench [milliseconds] [trials]
#                                  [continuation-steps] [3x3|5x5|7x7|all]

use ../lib/metaflip/rect

-> ttcs_expect(label, condition) (String bool) i64
  if !condition
    << "TWO_TERM_SWEEP_FAIL " + label
    exit(1)
  1

-> ttcs_apply(st, mode, first, second, axis) (i64[] i64 i64 i64 i64) i64
  rank_before = st[6] ## i64
  ui = st[st[44] + first] ## i64
  vi = st[st[45] + first] ## i64
  wi = st[st[46] + first] ## i64
  uj = st[st[44] + second] ## i64
  vj = st[st[45] + second] ## i64
  wj = st[st[46] + second] ## i64
  au = ui ## i64
  av = vi ## i64
  aw = wi ## i64
  bu = ui ## i64
  bv = vi ## i64
  bw = wj ## i64
  if axis == 0
    aw = wi ^ wj
    bv = vi ^ vj
  if axis == 1
    aw = wi ^ wj
    bu = ui ^ uj
  if axis == 2
    av = vi ^ vj
    bu = ui ^ uj
    bv = vj
    bw = wi
  old_pressure = 0 ## i64
  if mode == 0
    old_pressure = ffw_pressure_pair_balanced(st, ui, vi, wi, uj, vj, wj)
  old_bits = ffw_popcount(ui) + ffw_popcount(vi) + ffw_popcount(wi) ## i64
  old_bits += ffw_popcount(uj) + ffw_popcount(vj) + ffw_popcount(wj)
  rank = rank_before ## i64
  rank = ffw_remove_known_slot(st, first, rank)
  rank = ffw_remove_known_slot(st, second, rank)
  rank = ffw_toggle(st, au, av, aw, rank)
  rank = ffw_toggle(st, bu, bv, bw, rank)
  new_pressure = 0 ## i64
  if mode == 0
    new_pressure = ffw_pressure_pair_balanced(st, au, av, aw, bu, bv, bw)
  new_bits = ffw_popcount(au) + ffw_popcount(av) + ffw_popcount(aw) ## i64
  new_bits += ffw_popcount(bu) + ffw_popcount(bv) + ffw_popcount(bw)
  accept = 0 ## i64
  if rank < rank_before
    accept = 1
  if rank == rank_before
    if mode == 0
      pressure_slack = 6 - ((st[13] / 300000) % 7) ## i64
      if new_pressure + pressure_slack >= old_pressure && new_bits <= old_bits + st[17]
        accept = 1
    if mode != 0 && new_bits <= old_bits + st[17] + st[10]
      accept = 1
  if accept == 0
    rank = ffw_toggle(st, au, av, aw, rank)
    rank = ffw_toggle(st, bu, bv, bw, rank)
    rank = ffw_insert_known_absent(st, ui, vi, wi, rank)
    rank = ffw_insert_known_absent(st, uj, vj, wj, rank)
    st[22] += 1
    st[6] = rank_before
    return 0
  st[6] = rank
  if rank == rank_before
    st[64] += new_bits - old_bits
  if rank != rank_before
    st[64] = ffw_view_bits(st, st[44], st[45], st[46], st[50], rank) - st[36]
  st[21] += 1
  result = 1 ## i64
  adopted = ffw_adopt_algebraic(st, 1) ## i64
  if adopted == 2
    result = 2
  if adopted < 0
    result = 0 - 1
  result

# meta[0] fallback samples, meta[1] fallback legal hits.
-> ttcs_try_flip(st, mode, meta) (i64[] i64 i64[]) i64
  st[20] += 1
  rank = st[6] ## i64
  if rank < 2
    st[22] += 1
    return 0
  first_word = ffw_rand31(st) ## i64
  first_index = (first_word * rank) >> 31 ## i64
  first = st[st[50] + first_index] ## i64
  axis_word = ffw_rand31(st) ## i64
  start_axis = (((axis_word >> 22) & 511) * 3) >> 9 ## i64
  partner_word = ffw_rand31(st) ## i64
  axis = start_axis ## i64
  second = ffw_pick_partner(st, axis, first, partner_word) ## i64
  probe = 1 ## i64
  while second < 0 && probe < 3
    axis = (axis + 1) % 3
    second = ffw_pick_partner(st, axis, first, partner_word)
    probe += 1
  if second < 0
    meta[0] += 1
    # One fresh 31-bit draw maps uniformly onto the rank-1 live indices that
    # differ from the original first term; no rejection loop or extra sample.
    fallback_word = ffw_rand31(st) ## i64
    fallback_index = (fallback_word * (rank - 1)) >> 31 ## i64
    if fallback_index >= first_index
      fallback_index += 1
    first = st[st[50] + fallback_index]
    axis = start_axis
    second = ffw_pick_partner(st, axis, first, partner_word)
    probe = 1
    while second < 0 && probe < 3
      axis = (axis + 1) % 3
      second = ffw_pick_partner(st, axis, first, partner_word)
      probe += 1
    if second >= 0
      meta[1] += 1
  if second < 0
    st[23] += 1
    st[22] += 1
    return 0
  ttcs_apply(st, mode, first, second, axis)

-> ttcs_contains(values, value) i64
  i = 0 ## i64
  while i < values.size()
    if values[i] == value
      return 1
    i += 1
  0

-> ttcs_endpoint_id(st) (i64[]) i64
  digest = 0 ## i64
  sum = 0 ## i64
  i = 0 ## i64
  while i < st[6]
    slot = st[st[50] + i] ## i64
    term = ffw_term_zobrist(st[st[44] + slot], st[st[45] + slot], st[st[46] + slot]) ## i64
    digest = digest ^ term
    sum = (sum + term) & 9223372036854775807
    i += 1
  (digest ^ (sum >> 1) ^ (st[6] * 6364136223846793005)) & 9223372036854775807

-> ttcs_source_distance(st, us, vs, ws, rank) (i64[] i64[] i64[] i64[] i64) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < rank
    if ffw_find_term(st, us[i], vs[i], ws[i]) >= 0
      common += 1
    i += 1
  rank + st[6] - common - common

# stats: wall, calls, proposals, legal, accepted, rejected, misses, updates,
# current rank/bits, best rank/bits, source distance, endpoint, exact pair,
# fallback samples/hits.
-> ttcs_timed(path, n, expected_rank, seed, duration_ns, arm, stats) (String i64 i64 i64 i64 i64 i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  loaded = ffw_load_scheme_cap(st, path, n, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
  if loaded != expected_rank || ffw_verify_best_exact(st, n) != 1
    return 0
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  source_rank = ffw_export_best(st, source_u, source_v, source_w) ## i64
  before_proposals = ffw_proposals(st) ## i64
  before_accepted = ffw_accepted(st) ## i64
  before_rejected = ffw_rejected(st) ## i64
  before_misses = ffw_partner_misses(st) ## i64
  before_updates = ffw_best_updates(st) ## i64
  fallback = i64[2]
  started = ccall_nobox("__w_clock_ns_raw") ## i64
  elapsed = 0 ## i64
  calls = 0 ## i64
  while elapsed < duration_ns
    batch = 0 ## i64
    while batch < 4096
      mode = 0 ## i64
      if (calls % 5) >= 3
        mode = 1
      if arm == 0
        z = ffw_try_flip(st, mode) ## i64
      if arm == 1
        z = ffw_try_flip_axis_sweep(st, mode) ## i64
      if arm == 2
        z = ttcs_try_flip(st, mode, fallback) ## i64
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
  stats[8] = ffw_current_rank(st)
  stats[9] = ffw_current_bits(st)
  stats[10] = ffw_best_rank(st)
  stats[11] = ffw_best_bits(st)
  stats[12] = ttcs_source_distance(st, source_u, source_v, source_w, source_rank)
  stats[13] = ttcs_endpoint_id(st)
  stats[14] = ffw_verify_current_exact(st, n)
  stats[15] = ffw_verify_best_exact(st, n)
  stats[16] = fallback[0]
  stats[17] = fallback[1]
  # Retain the exact endpoint for continuation without making timed work pay
  # serialization.  The caller reloads this temporary certificate.
  out_path = "/tmp/ttcs_endpoint_" + n.to_s() + "_" + seed.to_s() + "_" + arm.to_s() + ".txt" ## String
  if ffw_dump_current(st, out_path) != st[6]
    return 0
  1

# result[0..1] receives best rank/bits for paired comparisons.
-> ttcs_continue(path, n, seed, steps, source_rank, source_bits, totals, result) (String i64 i64 i64 i64 i64 i64[] i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  endpoint_rank = ffw_load_scheme_cap(st, path, n, capacity, seed, 6, 4, 1000000000, 200000000) ## i64
  if endpoint_rank < 1 || ffw_verify_best_exact(st, n) != 1
    return 0
  endpoint_bits = ffw_best_bits(st) ## i64
  z = ffw_walk(st, steps) ## i64
  exact = ffw_verify_current_exact(st, n) * ffw_verify_best_exact(st, n) ## i64
  best_rank = ffw_best_rank(st) ## i64
  best_bits = ffw_best_bits(st) ## i64
  totals[0] += 1
  totals[1] += exact
  if best_rank < endpoint_rank
    totals[2] += 1
  if best_rank == endpoint_rank && best_bits < endpoint_bits
    totals[3] += 1
  if best_rank < source_rank || (best_rank == source_rank && best_bits < source_bits)
    totals[4] += 1
  totals[5] += best_rank
  totals[6] += best_bits
  totals[7] += ffw_best_updates(st)
  result[0] = best_rank
  result[1] = best_bits
  exact

-> ttcs_report_arm(name, totals, trials, unique, cont) (String i64[] i64 i64 i64[]) i64
  elapsed = totals[0] ## i64
  legal = totals[3] ## i64
  if elapsed < 1
    elapsed = 1
  if legal < 1
    legal = 1
  line = "TWO_TERM_SWEEP arm=" + name ## String
  line = line + " trials=" + trials.to_s() + " calls_per_s=" + (totals[1] * 1000000000 / elapsed).to_s()
  line = line + " legal_per_s=" + (totals[3] * 1000000000 / elapsed).to_s() + " accepted_per_s=" + (totals[4] * 1000000000 / elapsed).to_s()
  line = line + " legal=" + totals[3].to_s() + " accepted=" + totals[4].to_s() + " misses=" + totals[6].to_s()
  line = line + " accept_per_legal_ppm=" + (totals[4] * 1000000 / legal).to_s()
  line = line + " updates=" + totals[7].to_s() + " mean_rank=" + (totals[8] / trials).to_s() + " mean_bits=" + (totals[9] / trials).to_s()
  line = line + " mean_distance=" + (totals[12] / trials).to_s() + " unique=" + unique.to_s() + " exact=" + totals[14].to_s() + "/" + totals[15].to_s()
  line = line + " fallback_samples=" + totals[16].to_s() + " fallback_hits=" + totals[17].to_s()
  << line
  runs = cont[0] ## i64
  if runs < 1
    runs = 1
  cline = "TWO_TERM_SWEEP continuation arm=" + name ## String
  cline = cline + " runs=" + cont[0].to_s() + " exact=" + cont[1].to_s() + " rank_gains=" + cont[2].to_s() + " density_gains=" + cont[3].to_s()
  cline = cline + " source_wins=" + cont[4].to_s() + " mean_rank=" + (cont[5] / runs).to_s() + " mean_bits=" + (cont[6] / runs).to_s() + " updates=" + cont[7].to_s()
  << cline
  1

-> ttcs_shape(label, path, n, rank, duration_ns, trials, continuation_steps) (String String i64 i64 i64 i64 i64) i64
  source_capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(source_capacity)]
  source_loaded = ffw_load_scheme_cap(source, path, n, source_capacity, 319993, 6, 4, 1000000000, 200000000) ## i64
  z = ttcs_expect(label + " source load", source_loaded == rank && ffw_verify_best_exact(source, n) == 1) ## i64
  source_bits = ffw_best_bits(source) ## i64
  totals = [i64[18], i64[18], i64[18]]
  continuations = [i64[8], i64[8], i64[8]]
  ids = [[], [], []]
  tt_sweep_wins = 0 ## i64
  sweep_tt_wins = 0 ## i64
  tt_sweep_ties = 0 ## i64
  tt_base_wins = 0 ## i64
  base_tt_wins = 0 ## i64
  tt_base_ties = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 320003 + n * 65537 + trial * 7919 ## i64
    trial_stats = [i64[18], i64[18], i64[18]]
    order = [0, 1, 2]
    if trial % 3 == 1
      order = [1, 2, 0]
    if trial % 3 == 2
      order = [2, 0, 1]
    oi = 0 ## i64
    while oi < 3
      arm = order[oi] ## i64
      z = ttcs_expect(label + " timed exact", ttcs_timed(path, n, rank, seed, duration_ns, arm, trial_stats[arm]) == 1)
      z = ttcs_expect(label + " endpoint gates", trial_stats[arm][14] == 1 && trial_stats[arm][15] == 1)
      i = 0 ## i64
      while i < 18
        totals[arm][i] += trial_stats[arm][i]
        i += 1
      if ttcs_contains(ids[arm], trial_stats[arm][13]) == 0
        ids[arm].push(trial_stats[arm][13])
      oi += 1
    rep = 0 ## i64
    while rep < 3
      continuation_seed = 730003 + trial * 104729 + rep * 15485863 ## i64
      results = [i64[2], i64[2], i64[2]]
      arm = 0
      while arm < 3
        endpoint_path = "/tmp/ttcs_endpoint_" + n.to_s() + "_" + seed.to_s() + "_" + arm.to_s() + ".txt" ## String
        z = ttcs_expect(label + " continuation exact", ttcs_continue(endpoint_path, n, continuation_seed, continuation_steps, rank, source_bits, continuations[arm], results[arm]) == 1)
        arm += 1
      if results[2][0] < results[1][0] || (results[2][0] == results[1][0] && results[2][1] < results[1][1])
        tt_sweep_wins += 1
      if results[1][0] < results[2][0] || (results[1][0] == results[2][0] && results[1][1] < results[2][1])
        sweep_tt_wins += 1
      if results[2][0] == results[1][0] && results[2][1] == results[1][1]
        tt_sweep_ties += 1
      if results[2][0] < results[0][0] || (results[2][0] == results[0][0] && results[2][1] < results[0][1])
        tt_base_wins += 1
      if results[0][0] < results[2][0] || (results[0][0] == results[2][0] && results[0][1] < results[2][1])
        base_tt_wins += 1
      if results[2][0] == results[0][0] && results[2][1] == results[0][1]
        tt_base_ties += 1
      rep += 1
    trial += 1
  << "TWO_TERM_SWEEP tensor=" + label + " duration_ns=" + duration_ns.to_s() + " continuation_steps=" + continuation_steps.to_s()
  z = ttcs_report_arm("baseline", totals[0], trials, ids[0].size(), continuations[0]) ## i64
  z = ttcs_report_arm("axis-sweep", totals[1], trials, ids[1].size(), continuations[1])
  z = ttcs_report_arm("two-term", totals[2], trials, ids[2].size(), continuations[2])
  z = ttcs_expect(label + " fallback exercised", totals[2][16] > 0 && totals[2][17] > 0)
  << "TWO_TERM_SWEEP fertility tensor=" + label + " two/axis/tie=" + tt_sweep_wins.to_s() + "/" + sweep_tt_wins.to_s() + "/" + tt_sweep_ties.to_s() + " two/base/tie=" + tt_base_wins.to_s() + "/" + base_tt_wins.to_s() + "/" + tt_base_ties.to_s()
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
if shape == "all" || shape == "3x3"
  z = ttcs_shape("3x3", root + "matmul_3x3_rank23_d139_gf2.txt", 3, 23, duration_ns, trials, continuation_steps) ## i64
if shape == "all" || shape == "5x5"
  z = ttcs_shape("5x5", root + "matmul_5x5_rank93_d1155_gf2.txt", 5, 93, duration_ns, trials, continuation_steps) ## i64
if shape == "all" || shape == "7x7"
  z = ttcs_shape("7x7", root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 247, duration_ns, trials, continuation_steps) ## i64
<< "PASS bounded two-term collision-sweep audit"
