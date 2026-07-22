use flipfleet_fixed_rank_pocket
use flipfleet_bank_policy

-> fffrpwcb_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_WORD_CONTINUATION_FAIL " + label
    exit(1)
  1

-> fffrpwcb_state(scheme, seed, steps) (FFBCScheme i64 i64)
  capacity = ffw_default_capacity(7) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if scheme == nil || fffrp_scalar_scheme(scheme, us, vs, ws) != scheme.rank()
    return nil
  state = i64[ffw_state_size(capacity)]
  if ffw_init_terms_cap(state, us, vs, ws, scheme.rank(), 7, capacity, seed, 4, 1, steps, steps / 4) != scheme.rank()
    return nil
  if ffw_verify_best_exact(state, 7) != 1
    return nil
  state

-> fffrpwcb_better(left, right) (i64[] i64[]) i64
  if ffw_best_rank(left) < ffw_best_rank(right)
    return 1
  if ffw_best_rank(left) == ffw_best_rank(right) && ffw_best_bits(left) < ffw_best_bits(right)
    return 1
  0

-> fffrpwcb_one(source) (FFBCScheme)
  rank = source.rank() ## i64
  us = i64[rank]
  vs = i64[rank]
  ws = i64[rank]
  if fffrp_scalar_scheme(source, us, vs, ws) != rank
    return nil
  endpoint_u = i64[5]
  endpoint_v = i64[5]
  endpoint_w = i64[5]
  origins = i64[5]
  stats = i64[32]
  gain = fffrp_autonomous_ticket(us, vs, ws, rank, 1, 5, 5, 512, 12, endpoint_u, endpoint_v, endpoint_w, origins, stats) ## i64
  if gain != 10
    return nil
  fffrp_materialize_selected(source, origins, endpoint_u, endpoint_v, endpoint_w, stats[7])

-> fffrpwcb_run(label, root, word, trials, steps) (String FFBCScheme FFBCScheme i64 i64) i64
  one = fffrpwcb_one(root)
  fffrpwcb_expect("one-ticket " + label, one != nil)
  root_wins = 0 ## i64
  one_wins = 0 ## i64
  word_wins = 0 ## i64
  word_beats_root = 0 ## i64
  word_beats_one = 0 ## i64
  root_sum = 0 ## i64
  one_sum = 0 ## i64
  word_sum = 0 ## i64
  root_min = 999999999 ## i64
  one_min = 999999999 ## i64
  word_min = 999999999 ## i64
  started = ccall("__w_clock_ms") ## i64
  trial = 0 ## i64
  while trial < trials
    seed = 101003 + trial * 104729 ## i64
    root_state = fffrpwcb_state(root, seed, steps)
    one_state = fffrpwcb_state(one, seed, steps)
    word_state = fffrpwcb_state(word, seed, steps)
    fffrpwcb_expect("states " + label, root_state != nil && one_state != nil && word_state != nil)
    ffw_walk(root_state, steps)
    ffw_walk(one_state, steps)
    ffw_walk(word_state, steps)
    fffrpwcb_expect("exact " + label, ffw_verify_best_exact(root_state, 7) == 1 && ffw_verify_best_exact(one_state, 7) == 1 && ffw_verify_best_exact(word_state, 7) == 1)
    rb = ffw_best_bits(root_state) ## i64
    ob = ffw_best_bits(one_state) ## i64
    wb = ffw_best_bits(word_state) ## i64
    root_sum += rb
    one_sum += ob
    word_sum += wb
    if rb < root_min
      root_min = rb
    if ob < one_min
      one_min = ob
    if wb < word_min
      word_min = wb
    if fffrpwcb_better(word_state, root_state) == 1
      word_beats_root += 1
    if fffrpwcb_better(word_state, one_state) == 1
      word_beats_one += 1
    best = root_state
    arm = 0 ## i64
    if fffrpwcb_better(one_state, best) == 1
      best = one_state
      arm = 1
    if fffrpwcb_better(word_state, best) == 1
      arm = 2
    if arm == 0
      root_wins += 1
    if arm == 1
      one_wins += 1
    if arm == 2
      word_wins += 1
    trial += 1
  elapsed = ccall("__w_clock_ms") - started ## i64
  root_probe = fffrpwcb_state(root, 999001, steps)
  one_probe = fffrpwcb_state(one, 999003, steps)
  word_probe = fffrpwcb_state(word, 999005, steps)
  << "FIXED_RANK_POCKET_WORD_LONG shape=" + label + " trials=" + trials.to_s() + " steps=" + steps.to_s() + " wins-root/one/word=" + root_wins.to_s() + "/" + one_wins.to_s() + "/" + word_wins.to_s() + " word-beats-root/one=" + word_beats_root.to_s() + "/" + word_beats_one.to_s() + " min=" + root_min.to_s() + "/" + one_min.to_s() + "/" + word_min.to_s() + " avg=" + (root_sum / trials).to_s() + "/" + (one_sum / trials).to_s() + "/" + (word_sum / trials).to_s() + " basin=" + ffbi_best_id(root_probe).to_s() + "/" + ffbi_best_id(one_probe).to_s() + "/" + ffbi_best_id(word_probe).to_s() + " signature=" + ffbp_structural_signature(root_probe).to_s() + "/" + ffbp_structural_signature(one_probe).to_s() + "/" + ffbp_structural_signature(word_probe).to_s() + " distance-root/one=" + ffbp_distance(root_probe, word_probe).to_s() + "/" + ffbp_distance(one_probe, word_probe).to_s() + " elapsed-ms=" + elapsed.to_s()
  word_wins

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
bench = "benchmarks/matmul/metaflip/"
c013 = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260)
child = ffbc_load_exact(root + "matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 7, 7, 260)
word3524 = ffbc_load_exact(bench + "matmul_7x7_rank247_d3524_fixed_rank_pocket_word_gf2.txt", 7, 7, 7, 260)
word3516 = ffbc_load_exact(bench + "matmul_7x7_rank247_d3516_fixed_rank_pocket_word_gf2.txt", 7, 7, 7, 260)
closure3496 = ffbc_load_exact(bench + "matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt", 7, 7, 7, 260)
fffrpwcb_expect("load", c013 != nil && child != nil && word3524 != nil && word3516 != nil && closure3496 != nil)
wins = fffrpwcb_run("7x7-c013", c013, word3524, 24, 1000000) ## i64
wins += fffrpwcb_run("7x7-c013-child", child, word3516, 24, 1000000)
wins += fffrpwcb_run("7x7-c013-greedy", c013, closure3496, 24, 1000000)
wins += fffrpwcb_run("7x7-c013-child-greedy", child, closure3496, 24, 1000000)
<< "FIXED_RANK_POCKET_WORD_LONG_DONE word-arm-wins=" + wins.to_s()
