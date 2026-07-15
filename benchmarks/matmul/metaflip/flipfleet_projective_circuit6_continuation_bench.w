# Equal-move fertility control for the best 5x5 six-circuit +2 shoulder
# against two ordinary exact +1 splits from the same rank-93 source.

use flipfleet_projective_circuit6
use flipfleet_global_isotropy

-> ffpc6cb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_CIRCUIT6_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
trials = 8 ## i64
moves = 5000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
ffpc6cb_expect("arguments",trials >= 1 && trials <= 64 && moves >= 1 && moves <= 2000000000)

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt",n,capacity,97201,4,4,500000,100000) ## i64
ffpc6cb_expect("base",base_rank == 93 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffpc6cb_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

circuit_u = i64[capacity]
circuit_v = i64[capacity]
circuit_w = i64[capacity]
circuit_meta = i64[18]
circuit_rank = ffpc6_search(base_u,base_v,base_w,base_rank,0,0,0,circuit_u,circuit_v,circuit_w,circuit_meta) ## i64
ffpc6cb_expect("circuit shoulder",circuit_rank == 95 && circuit_meta[12] == 2)
circuit_distance = ffgir_term_set_distance(base_u,base_v,base_w,base_rank,circuit_u,circuit_v,circuit_w,circuit_rank) ## i64
ffpc6cb_expect("circuit distance",circuit_distance >= 8)
circuit_gate = i64[state_size]
ffpc6cb_expect("circuit exact",ffw_init_terms_cap(circuit_gate,circuit_u,circuit_v,circuit_w,circuit_rank,n,capacity,97203,4,4,500000,100000) == 95 && ffw_verify_current_exact(circuit_gate,n) == 1)

circuit_returns = 0 ## i64
split_returns = 0 ## i64
circuit_rank_wins = 0 ## i64
split_rank_wins = 0 ## i64
circuit_density_wins = 0 ## i64
split_density_wins = 0 ## i64
circuit_novel = 0 ## i64
split_novel = 0 ## i64
circuit_distance_sum = 0 ## i64
split_distance_sum = 0 ## i64
circuit_beats = 0 ## i64
split_beats = 0 ## i64
ties = 0 ## i64

started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  split_builder = i64[state_size]
  split_loaded = ffw_init_terms_cap(split_builder,base_u,base_v,base_w,base_rank,n,capacity,97301 + trial * 132,4,4,500000,100000) ## i64
  ffpc6cb_expect("split init",split_loaded == 93)
  tries = 0 ## i64
  while ffw_current_rank(split_builder) < 95 && tries < 4096
    z = ffw_try_split(split_builder) ## i64
    tries += 1
  ffpc6cb_expect("two splits",ffw_current_rank(split_builder) == 95 && ffw_verify_current_exact(split_builder,n) == 1)
  split_u = i64[capacity]
  split_v = i64[capacity]
  split_w = i64[capacity]
  split_rank = ffw_export_current(split_builder,split_u,split_v,split_w) ## i64
  ffpc6cb_expect("split export",split_rank == 95)

  trial_rank = i64[2]
  trial_bits = i64[2]
  arm = 0 ## i64
  while arm < 2
    state = i64[state_size]
    seed = 97401 + trial * 104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = 0 ## i64
    if arm == 0
      loaded = ffw_init_terms_cap(state,circuit_u,circuit_v,circuit_w,circuit_rank,n,capacity,seed,4,4,workq,wanderq)
    else
      loaded = ffw_init_terms_cap(state,split_u,split_v,split_w,split_rank,n,capacity,seed,4,4,workq,wanderq)
    ffpc6cb_expect("walk init",loaded == 95)
    z = ffw_walk(state,moves)
    ffpc6cb_expect("walk exact",ffw_verify_best_exact(state,n) == 1)
    trial_rank[arm] = ffw_best_rank(state)
    trial_bits[arm] = ffw_best_bits(state)
    endpoint_u = i64[capacity]
    endpoint_v = i64[capacity]
    endpoint_w = i64[capacity]
    z = ffw_export_best(state,endpoint_u,endpoint_v,endpoint_w)
    distance = ffgir_term_set_distance(base_u,base_v,base_w,base_rank,endpoint_u,endpoint_v,endpoint_w,trial_rank[arm]) ## i64
    if arm == 0
      if trial_rank[arm] <= base_rank
        circuit_returns += 1
      if trial_rank[arm] < base_rank
        circuit_rank_wins += 1
      if trial_rank[arm] == base_rank && trial_bits[arm] < 968
        circuit_density_wins += 1
      if trial_rank[arm] == base_rank && distance > 0
        circuit_novel += 1
      circuit_distance_sum += distance
    else
      if trial_rank[arm] <= base_rank
        split_returns += 1
      if trial_rank[arm] < base_rank
        split_rank_wins += 1
      if trial_rank[arm] == base_rank && trial_bits[arm] < 968
        split_density_wins += 1
      if trial_rank[arm] == base_rank && distance > 0
        split_novel += 1
      split_distance_sum += distance
    arm += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    circuit_beats += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[0] == trial_rank[1] && trial_bits[1] < trial_bits[0])
    split_beats += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  << "PROJECTIVE_CIRCUIT6_CONTINUATION trial=" + trial.to_s() + " circuit=r" + trial_rank[0].to_s() + "/d" + trial_bits[0].to_s() + " split=r" + trial_rank[1].to_s() + "/d" + trial_bits[1].to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64
<< "PROJECTIVE_CIRCUIT6_CONTINUATION_SEED rank=" + circuit_rank.to_s() + " density=" + circuit_meta[11].to_s() + " distance=" + circuit_distance.to_s()
<< "PROJECTIVE_CIRCUIT6_CONTINUATION_SUMMARY trials=" + trials.to_s() + " moves=" + moves.to_s() + " returns=" + circuit_returns.to_s() + "/" + split_returns.to_s() + " rank_wins=" + circuit_rank_wins.to_s() + "/" + split_rank_wins.to_s() + " density_wins=" + circuit_density_wins.to_s() + "/" + split_density_wins.to_s() + " novel=" + circuit_novel.to_s() + "/" + split_novel.to_s() + " distance_avg=" + (circuit_distance_sum / trials).to_s() + "/" + (split_distance_sum / trials).to_s() + " match=" + circuit_beats.to_s() + "/" + split_beats.to_s() + "/" + ties.to_s() + " aggregate_moves=" + (trials * moves * 2).to_s() + " ms=" + elapsed.to_s()
