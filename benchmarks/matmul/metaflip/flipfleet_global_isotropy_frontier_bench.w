use flipfleet_global_isotropy

-> ffgirfb_unique(values, count) (i64[] i64) i64
  unique = 0 ## i64
  i = 0 ## i64
  while i < count
    seen = 0 ## i64
    j = 0 ## i64
    while j < i && seen == 0
      if values[j] == values[i]
        seen = 1
      j += 1
    if seen == 0
      unique += 1
    i += 1
  unique

-> ffgirfb_run(left_path, right_path, output_path, n, trials, steps) (String String String i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  size = ffw_state_size(capacity) ## i64
  left_source = i64[size]
  right_source = i64[size]
  left_rank = ffw_load_scheme_cap(left_source, left_path, n, capacity, 701, 6, 4, 100000, 25000) ## i64
  right_rank = ffw_load_scheme_cap(right_source, right_path, n, capacity, 703, 6, 4, 100000, 25000) ## i64
  if left_rank < 1 || left_rank != right_rank || ffw_verify_best_exact(left_source, n) != 1 || ffw_verify_best_exact(right_source, n) != 1
    << "GLOBAL_ISOTROPY_FRONTIER_LOAD_FAIL"
    return 0
  left_record = i64[size]
  if ffw_reseed_from(left_record, left_source, 709) != left_rank
    return 0

  left_u = i64[capacity]
  left_v = i64[capacity]
  left_w = i64[capacity]
  right_u = i64[capacity]
  right_v = i64[capacity]
  right_w = i64[capacity]
  z = ffw_export_best(left_source, left_u, left_v, left_w) ## i64
  z = ffw_export_best(right_source, right_u, right_v, right_w)
  left_start = ffw_best_bits(left_source) ## i64
  right_start = ffw_best_bits(right_source) ## i64
  left_best_min = left_start ## i64
  right_best_min = right_start ## i64
  left_best_sum = 0 ## i64
  right_best_sum = 0 ## i64
  left_accept_sum = 0 ## i64
  right_accept_sum = 0 ## i64
  left_distance_sum = 0 ## i64
  right_distance_sum = 0 ## i64
  left_rank_wins = 0 ## i64
  right_rank_wins = 0 ## i64
  left_density_wins = 0 ## i64
  right_density_wins = 0 ## i64
  left_ids = i64[trials]
  right_ids = i64[trials]
  left_gls = i64[trials]
  right_gls = i64[trials]
  workq = steps / 16 ## i64
  wanderq = steps / 32 ## i64
  if workq < 1
    workq = 1
  if wanderq < 1
    wanderq = 1

  trial = 0 ## i64
  while trial < trials
    seed = 65537 * (trial + 1) + n * 1009 ## i64
    left = i64[size]
    right = i64[size]
    if ffw_init_terms_cap(left, left_u, left_v, left_w, left_rank, n, capacity, seed, 6, 4, workq, wanderq) != left_rank
      return 0
    if ffw_init_terms_cap(right, right_u, right_v, right_w, right_rank, n, capacity, seed, 6, 4, workq, wanderq) != right_rank
      return 0
    z = ffw_walk(left, steps)
    z = ffw_walk(right, steps)
    if ffw_verify_current_exact(left, n) != 1 || ffw_verify_current_exact(right, n) != 1
      return 0

    left_best = ffw_best_bits(left) ## i64
    right_best = ffw_best_bits(right) ## i64
    left_best_sum += left_best
    right_best_sum += right_best
    if left_best < left_best_min
      left_best_min = left_best
      if ffw_reseed_from(left_record, left, 710 + trial) != left_rank
        return 0
    if right_best < right_best_min
      right_best_min = right_best
    if ffw_best_rank(left) < left_rank
      left_rank_wins += 1
    else
      if left_best < left_start
        left_density_wins += 1
    if ffw_best_rank(right) < right_rank
      right_rank_wins += 1
    else
      if right_best < right_start
        right_density_wins += 1
    left_accept_sum += ffw_accepted(left)
    right_accept_sum += ffw_accepted(right)

    lu = i64[capacity]
    lv = i64[capacity]
    lw = i64[capacity]
    ru = i64[capacity]
    rv = i64[capacity]
    rw = i64[capacity]
    lr = ffw_export_current(left, lu, lv, lw) ## i64
    rr = ffw_export_current(right, ru, rv, rw) ## i64
    left_distance_sum += ffgir_term_set_distance(left_u, left_v, left_w, left_rank, lu, lv, lw, lr)
    right_distance_sum += ffgir_term_set_distance(right_u, right_v, right_w, right_rank, ru, rv, rw, rr)
    left_ids[trial] = ffbi_current_id(left)
    right_ids[trial] = ffbi_current_id(right)
    left_gls[trial] = ffbi_gl_invariant_view(left, 1)
    right_gls[trial] = ffbi_gl_invariant_view(right, 1)
    trial += 1

  dumped = ffw_dump_best(left_record, output_path) ## i64
  reparsed = i64[size]
  reloaded = ffw_load_scheme_cap(reparsed, output_path, n, capacity, 719, 6, 4, workq, wanderq) ## i64
  if dumped != left_rank || reloaded != left_rank || ffw_best_bits(reparsed) != left_best_min || ffw_verify_best_exact(reparsed, n) != 1
    return 0
  << "GLOBAL_ISOTROPY_FRONTIER_SUMMARY n=" + n.to_s() + " rank=" + left_rank.to_s() + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " start-density=" + left_start.to_s() + "/" + right_start.to_s() + " start-distance=" + ffgir_term_set_distance(left_u, left_v, left_w, left_rank, right_u, right_v, right_w, right_rank).to_s() + " best-density-min=" + left_best_min.to_s() + "/" + right_best_min.to_s() + " best-density-avg=" + (left_best_sum / trials).to_s() + "/" + (right_best_sum / trials).to_s() + " rank-win=" + left_rank_wins.to_s() + "/" + right_rank_wins.to_s() + " density-win=" + left_density_wins.to_s() + "/" + right_density_wins.to_s() + " accepted-avg=" + (left_accept_sum / trials).to_s() + "/" + (right_accept_sum / trials).to_s() + " desc-d-avg=" + (left_distance_sum / trials).to_s() + "/" + (right_distance_sum / trials).to_s() + " unique-id=" + ffgirfb_unique(left_ids, trials).to_s() + "/" + ffgirfb_unique(right_ids, trials).to_s() + " unique-gl=" + ffgirfb_unique(left_gls, trials).to_s() + "/" + ffgirfb_unique(right_gls, trials).to_s() + " exact=1 reparsed=1 output=" + output_path
  1

arguments = argv()
trials = 24 ## i64
steps = 2000000 ## i64
output = "/tmp/matmul_5x5_rank93_shortwalk_global_isotropy_gf2.txt"
left_path = ""
right_path = ""
n = 5 ## i64
if arguments.size() > 0
  trials = arguments[0].to_i()
if arguments.size() > 1
  steps = arguments[1].to_i()
if arguments.size() > 2
  output = arguments[2]
if arguments.size() > 3
  left_path = arguments[3]
if arguments.size() > 4
  right_path = arguments[4]
if arguments.size() > 5
  n = arguments[5].to_i()
if trials < 1
  trials = 1
if trials > 128
  trials = 128
if steps < 1
  steps = 1
if steps > 20000000
  steps = 20000000

root = "benchmarks/matmul/metaflip/"
if left_path == ""
  left_path = root + "matmul_5x5_rank93_d983_global_isotropy_gf2.txt"
if right_path == ""
  right_path = root + "matmul_5x5_rank93_d1155_gf2.txt"
ok = ffgirfb_run(left_path, right_path, output, n, trials, steps) ## i64
if ok != 1
  exit(1)
