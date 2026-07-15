# Equal-move fertility control for the best complete 5x5 rank-two dependency
# shoulder against an ordinary exact +1 split from the same rank-93 source.

use flipfleet_gf2_lowrank_dependency_median
use flipfleet_global_isotropy
use flipfleet_escape

-> fflrdcb_expect(label, condition) (String bool) i64
  if !condition
    << "GF2_LOWRANK_DEPENDENCY_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
trials = 12 ## i64
moves = 10000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
fflrdcb_expect("arguments",trials >= 1 && trials <= 64 && moves >= 1 && moves <= 2000000000)

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_5x5_rank93_d967_four_split_control_gf2.txt",n,capacity,1004001,4,4,500000,100000) ## i64
fflrdcb_expect("base",base_rank == 93 && ffw_current_bits(base) == 967 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
fflrdcb_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

lowrank_state = i64[state_size]
lowrank_meta = i64[41]
lowrank_rank = fflrd_search_state_filtered(base,0,1,0,2,2,lowrank_state,lowrank_meta) ## i64
fflrdcb_expect("rank-two shoulder",lowrank_rank == 94 && lowrank_meta[24] == 975 && lowrank_meta[28] == 2 && ffw_verify_current_exact(lowrank_state,n) == 1)
lowrank_u = i64[capacity]
lowrank_v = i64[capacity]
lowrank_w = i64[capacity]
fflrdcb_expect("rank-two export",ffw_export_current(lowrank_state,lowrank_u,lowrank_v,lowrank_w) == lowrank_rank)

returns = i64[2]
rank_wins = i64[2]
density_wins = i64[2]
novel = i64[2]
distance_sum = i64[2]
best_rank = i64[2]
best_bits = i64[2]
best_rank[0] = 1000
best_rank[1] = 1000
best_bits[0] = 9223372036854775807
best_bits[1] = 9223372036854775807
lowrank_beats = 0 ## i64
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
  fflrdcb_expect("split shoulder",split_rank == 94)
  split_gate = i64[state_size]
  fflrdcb_expect("split exact",ffw_init_terms_cap(split_gate,split_u,split_v,split_w,split_rank,n,capacity,1005001 + trial,4,4,500000,100000) == 94 && ffw_verify_current_exact(split_gate,n) == 1)

  trial_rank = i64[2]
  trial_bits = i64[2]
  arm = 0 ## i64
  while arm < 2
    state = i64[state_size]
    walk_seed = 1006001 + trial * 104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = 0 ## i64
    if arm == 0
      loaded = ffw_init_terms_cap(state,lowrank_u,lowrank_v,lowrank_w,lowrank_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    else
      loaded = ffw_init_terms_cap(state,split_u,split_v,split_w,split_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    fflrdcb_expect("walk init",loaded == 94)
    z = ffw_walk(state,moves) ## i64
    fflrdcb_expect("walk exact",ffw_verify_best_exact(state,n) == 1)
    trial_rank[arm] = ffw_best_rank(state)
    trial_bits[arm] = ffw_best_bits(state)
    endpoint_u = i64[capacity]
    endpoint_v = i64[capacity]
    endpoint_w = i64[capacity]
    z = ffw_export_best(state,endpoint_u,endpoint_v,endpoint_w)
    distance = ffgir_term_set_distance(base_u,base_v,base_w,base_rank,endpoint_u,endpoint_v,endpoint_w,trial_rank[arm]) ## i64
    if trial_rank[arm] <= base_rank
      returns[arm] = returns[arm] + 1
    if trial_rank[arm] < base_rank
      rank_wins[arm] = rank_wins[arm] + 1
    if trial_rank[arm] == base_rank && trial_bits[arm] < 967
      density_wins[arm] = density_wins[arm] + 1
    if trial_rank[arm] == base_rank && distance > 0
      novel[arm] = novel[arm] + 1
    distance_sum[arm] = distance_sum[arm] + distance
    if trial_rank[arm] < best_rank[arm] || (trial_rank[arm] == best_rank[arm] && trial_bits[arm] < best_bits[arm])
      best_rank[arm] = trial_rank[arm]
      best_bits[arm] = trial_bits[arm]
    arm += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    lowrank_beats += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[0] == trial_rank[1] && trial_bits[1] < trial_bits[0])
    split_beats += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  << "GF2_LOWRANK_DEPENDENCY_CONTINUATION trial=" + trial.to_s() + " lowrank=r" + trial_rank[0].to_s() + "/d" + trial_bits[0].to_s() + " split=r" + trial_rank[1].to_s() + "/d" + trial_bits[1].to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64
arm = 0
while arm < 2
  label = "lowrank"
  if arm == 1
    label = "split"
  << "GF2_LOWRANK_DEPENDENCY_ARM " + label + " returns=" + returns[arm].to_s() + " rank_wins=" + rank_wins[arm].to_s() + " density_wins=" + density_wins[arm].to_s() + " novel=" + novel[arm].to_s() + " distance_avg=" + (distance_sum[arm] / trials).to_s() + " best=r" + best_rank[arm].to_s() + "/d" + best_bits[arm].to_s()
  arm += 1
<< "GF2_LOWRANK_DEPENDENCY_MATCH beats=" + lowrank_beats.to_s() + "/" + split_beats.to_s() + " ties=" + ties.to_s()
<< "GF2_LOWRANK_DEPENDENCY_SUMMARY trials=" + trials.to_s() + " moves=" + moves.to_s() + " aggregate=" + (trials * moves * 2).to_s() + " ms=" + elapsed.to_s()
