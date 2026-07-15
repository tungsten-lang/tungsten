# Equal-move fertility control for the best 5x5 five-bucket +1 shoulder
# against one ordinary exact +1 split from the same rank-93 source.

use flipfleet_projective_circuit5
use flipfleet_global_isotropy
use flipfleet_escape

-> ffpc5cb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_CIRCUIT5_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
trials = 12 ## i64
moves = 10000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
ffpc5cb_expect("arguments",trials >= 1 && trials <= 64 && moves >= 1 && moves <= 2000000000)

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_5x5_rank93_d967_four_split_control_gf2.txt",n,capacity,96201,4,4,500000,100000) ## i64
ffpc5cb_expect("base",base_rank == 93 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffpc5cb_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

circuit_u = i64[capacity]
circuit_v = i64[capacity]
circuit_w = i64[capacity]
circuit_meta = i64[14]
circuit_rank = ffpc5_search(base_u,base_v,base_w,base_rank,0,0,circuit_u,circuit_v,circuit_w,circuit_meta) ## i64
ffpc5cb_expect("circuit shoulder",circuit_rank == 94 && circuit_meta[9] == 1)
circuit_gate = i64[state_size]
ffpc5cb_expect("circuit exact",ffw_init_terms_cap(circuit_gate,circuit_u,circuit_v,circuit_w,circuit_rank,n,capacity,96203,4,4,500000,100000) == 94 && ffw_verify_current_exact(circuit_gate,n) == 1)

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
circuit_best_rank = 1000 ## i64
split_best_rank = 1000 ## i64
circuit_best_bits = 9223372036854775807 ## i64
split_best_bits = 9223372036854775807 ## i64
circuit_beats = 0 ## i64
split_beats = 0 ## i64
ties = 0 ## i64

started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  split_u = i64[capacity]
  split_v = i64[capacity]
  split_w = i64[capacity]
  split_rank = 0 ## i64
  attempt = 0 ## i64
  while attempt < base_rank * 3 && split_rank != 94
    i = 0 ## i64
    while i < base_rank
      split_u[i] = base_u[i]
      split_v[i] = base_v[i]
      split_w[i] = base_w[i]
      i += 1
    split_meta = i64[8]
    source = (trial * 17 + attempt * 7) % base_rank ## i64
    axis = (trial + attempt) % 3 ## i64
    split_rank = ffe_split(split_u,split_v,split_w,base_rank,capacity,source,axis,split_meta)
    attempt += 1
  ffpc5cb_expect("split shoulder",split_rank == 94)
  split_gate = i64[state_size]
  ffpc5cb_expect("split exact",ffw_init_terms_cap(split_gate,split_u,split_v,split_w,split_rank,n,capacity,96301 + trial,4,4,500000,100000) == 94 && ffw_verify_current_exact(split_gate,n) == 1)

  trial_rank = i64[2]
  trial_bits = i64[2]
  arm = 0 ## i64
  while arm < 2
    state = i64[state_size]
    walk_seed = 96401 + trial * 104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = 0 ## i64
    if arm == 0
      loaded = ffw_init_terms_cap(state,circuit_u,circuit_v,circuit_w,circuit_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    else
      loaded = ffw_init_terms_cap(state,split_u,split_v,split_w,split_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    ffpc5cb_expect("walk init",loaded == 94)
    z = ffw_walk(state,moves) ## i64
    ffpc5cb_expect("walk exact",ffw_verify_best_exact(state,n) == 1)
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
      if trial_rank[arm] == base_rank && trial_bits[arm] < 967
        circuit_density_wins += 1
      if trial_rank[arm] < circuit_best_rank || (trial_rank[arm] == circuit_best_rank && trial_bits[arm] < circuit_best_bits)
        circuit_best_rank = trial_rank[arm]
        circuit_best_bits = trial_bits[arm]
      circuit_distance_sum += distance
      if trial_rank[arm] == base_rank && distance > 0
        circuit_novel += 1
    else
      if trial_rank[arm] <= base_rank
        split_returns += 1
      if trial_rank[arm] < base_rank
        split_rank_wins += 1
      if trial_rank[arm] == base_rank && trial_bits[arm] < 967
        split_density_wins += 1
      if trial_rank[arm] < split_best_rank || (trial_rank[arm] == split_best_rank && trial_bits[arm] < split_best_bits)
        split_best_rank = trial_rank[arm]
        split_best_bits = trial_bits[arm]
      split_distance_sum += distance
      if trial_rank[arm] == base_rank && distance > 0
        split_novel += 1
    arm += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    circuit_beats += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[0] == trial_rank[1] && trial_bits[1] < trial_bits[0])
    split_beats += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  << "PROJECTIVE_CIRCUIT5_CONTINUATION trial=" + trial.to_s() + " circuit=r" + trial_rank[0].to_s() + "/d" + trial_bits[0].to_s() + " split=r" + trial_rank[1].to_s() + "/d" + trial_bits[1].to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64
circuit_distance_avg = circuit_distance_sum / trials ## i64
split_distance_avg = split_distance_sum / trials ## i64
aggregate_moves = trials * moves * 2 ## i64
<< "PROJECTIVE_CIRCUIT5_ARM circuit returns=" + circuit_returns.to_s() + " rank_wins=" + circuit_rank_wins.to_s() + " density_wins=" + circuit_density_wins.to_s()
<< "PROJECTIVE_CIRCUIT5_ARM circuit novel=" + circuit_novel.to_s() + " distance_avg=" + circuit_distance_avg.to_s()
<< "PROJECTIVE_CIRCUIT5_ARM circuit best_rank=" + circuit_best_rank.to_s() + " best_bits=" + circuit_best_bits.to_s()
<< "PROJECTIVE_CIRCUIT5_ARM split returns=" + split_returns.to_s() + " rank_wins=" + split_rank_wins.to_s() + " density_wins=" + split_density_wins.to_s()
<< "PROJECTIVE_CIRCUIT5_ARM split novel=" + split_novel.to_s() + " distance_avg=" + split_distance_avg.to_s()
<< "PROJECTIVE_CIRCUIT5_ARM split best_rank=" + split_best_rank.to_s() + " best_bits=" + split_best_bits.to_s()
<< "PROJECTIVE_CIRCUIT5_MATCH beats=" + circuit_beats.to_s() + "/" + split_beats.to_s() + " ties=" + ties.to_s()
<< "PROJECTIVE_CIRCUIT5_SUMMARY trials=" + trials.to_s() + " moves=" + moves.to_s() + " aggregate=" + aggregate_moves.to_s() + " ms=" + elapsed.to_s()
