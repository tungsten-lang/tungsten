# Equal-move ordinary FlipFleet continuations from the two depth-4,
# source-disjoint partial-automorphism beam endpoints and the density leader.

use flipfleet_global_isotropy

-> ffpanblc_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_BEAM_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
moves = 20000000 ## i64
trials = 4 ## i64
if args.size() > 0
  moves = args[0].to_i()
if args.size() > 1
  trials = args[1].to_i()
ffpanblc_expect("arguments", moves >= 1 && trials >= 1 && trials <= 32)

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
root_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
paths = ["benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt", "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt"]

root = i64[state_size]
root_rank = ffw_load_scheme_cap(root, root_path, n, capacity, 992001, 0, 1, 1, 1) ## i64
ffpanblc_expect("root", root_rank == 247 && ffw_verify_best_exact(root, n) == 1)
endpoint_rank_wins = 0 ## i64
endpoint_density_wins = 0 ## i64
control_rank_wins = 0 ## i64
control_density_wins = 0 ## i64
endpoint_accepts = 0 ## i64
control_accepts = 0 ## i64
arm = 0 ## i64
while arm < paths.size()
  seed_state = i64[state_size]
  seed_rank = ffw_load_scheme_cap(seed_state, paths[arm], n, capacity, 992101 + arm, 0, 1, 1, 1) ## i64
  ffpanblc_expect("endpoint", seed_rank == 247 && ffw_verify_best_exact(seed_state, n) == 1 && ffw_best_bits(seed_state) == 3098)
  trial = 0 ## i64
  while trial < trials
    seed = 993001 + arm * 1009 + trial * 101 ## i64
    workq = moves / 4 ## i64
    wanderq = moves / 16 ## i64
    endpoint = i64[state_size]
    control = i64[state_size]
    endpoint_loaded = ffw_load_scheme_cap(endpoint, paths[arm], n, capacity, seed, 4, 4, workq, wanderq) ## i64
    control_loaded = ffw_load_scheme_cap(control, root_path, n, capacity, seed, 4, 4, workq, wanderq) ## i64
    ffpanblc_expect("walk loads", endpoint_loaded == 247 && control_loaded == 247)
    ffw_walk(endpoint, moves)
    ffw_walk(control, moves)
    ffpanblc_expect("walk exact", ffw_verify_best_exact(endpoint, n) == 1 && ffw_verify_best_exact(control, n) == 1)
    erank = ffw_best_rank(endpoint) ## i64
    ebits = ffw_best_bits(endpoint) ## i64
    crank = ffw_best_rank(control) ## i64
    cbits = ffw_best_bits(control) ## i64
    if erank < 247
      endpoint_rank_wins += 1
    if erank == 247 && ebits < 3098
      endpoint_density_wins += 1
    if crank < 247
      control_rank_wins += 1
    if crank == 247 && cbits < 3098
      control_density_wins += 1
    endpoint_accepts += ffw_accepted(endpoint)
    control_accepts += ffw_accepted(control)
    << "PARTIAL_AUTOMORPHISM_BEAM_LONG_CONTINUATION arm=" + arm.to_s() + " trial=" + trial.to_s() + " moves=" + moves.to_s() + " endpoint=r" + erank.to_s() + "/d" + ebits.to_s() + "/a" + ffw_accepted(endpoint).to_s() + " control=r" + crank.to_s() + "/d" + cbits.to_s() + "/a" + ffw_accepted(control).to_s()
    trial += 1
  arm += 1

total = paths.size() * trials ## i64
<< "PARTIAL_AUTOMORPHISM_BEAM_LONG_CONTINUATION_SUMMARY arms=" + total.to_s() + " moves/arm=" + moves.to_s() + " endpoint_rank_wins=" + endpoint_rank_wins.to_s() + " endpoint_density_wins=" + endpoint_density_wins.to_s() + " control_rank_wins=" + control_rank_wins.to_s() + " control_density_wins=" + control_density_wins.to_s() + " accepts=" + endpoint_accepts.to_s() + "/" + control_accepts.to_s()
