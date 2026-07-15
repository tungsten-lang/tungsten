# Equal-move fertility control for the best 6x6 polynomial-median +1 shoulder
# against an ordinary exact +1 split from the same rank-153 source.

use flipfleet_gf2_dependency_median
use flipfleet_global_isotropy
use flipfleet_escape

-> ffgdmcb_expect(label, condition) (String bool) i64
  if !condition
    << "GF2_DEPENDENCY_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
trials = 12 ## i64
moves = 10000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
ffgdmcb_expect("arguments",trials >= 1 && trials <= 64 && moves >= 1 && moves <= 2000000000)

n = 6 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt",n,capacity,995001,4,4,500000,100000) ## i64
ffgdmcb_expect("base",base_rank == 153 && ffw_current_bits(base) == 1860 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffgdmcb_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

median_state = i64[state_size]
median_meta = i64[32]
median_rank = ffgdm_search_state(base,0,1,64,median_state,median_meta) ## i64
ffgdmcb_expect("median shoulder",median_rank == 154 && median_meta[19] == 1840 && ffw_verify_current_exact(median_state,n) == 1)
median_u = i64[capacity]
median_v = i64[capacity]
median_w = i64[capacity]
ffgdmcb_expect("median export",ffw_export_current(median_state,median_u,median_v,median_w) == median_rank)

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
median_beats = 0 ## i64
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
  while attempt < base_rank * 3 && split_rank != 154
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
  ffgdmcb_expect("split shoulder",split_rank == 154)
  split_gate = i64[state_size]
  ffgdmcb_expect("split exact",ffw_init_terms_cap(split_gate,split_u,split_v,split_w,split_rank,n,capacity,996001 + trial,4,4,500000,100000) == 154 && ffw_verify_current_exact(split_gate,n) == 1)
  trial_rank = i64[2]
  trial_bits = i64[2]
  arm = 0 ## i64
  while arm < 2
    state = i64[state_size]
    walk_seed = 997001 + trial * 104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = 0 ## i64
    if arm == 0
      loaded = ffw_init_terms_cap(state,median_u,median_v,median_w,median_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    else
      loaded = ffw_init_terms_cap(state,split_u,split_v,split_w,split_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    ffgdmcb_expect("walk init",loaded == 154)
    z = ffw_walk(state,moves) ## i64
    ffgdmcb_expect("walk exact",ffw_verify_best_exact(state,n) == 1)
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
    if trial_rank[arm] == base_rank && trial_bits[arm] < 1860
      density_wins[arm] = density_wins[arm] + 1
    if trial_rank[arm] == base_rank && distance > 0
      novel[arm] = novel[arm] + 1
    distance_sum[arm] = distance_sum[arm] + distance
    if trial_rank[arm] < best_rank[arm] || (trial_rank[arm] == best_rank[arm] && trial_bits[arm] < best_bits[arm])
      best_rank[arm] = trial_rank[arm]
      best_bits[arm] = trial_bits[arm]
    arm += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    median_beats += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[0] == trial_rank[1] && trial_bits[1] < trial_bits[0])
    split_beats += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  << "GF2_DEPENDENCY_CONTINUATION trial=" + trial.to_s() + " median=r" + trial_rank[0].to_s() + "/d" + trial_bits[0].to_s() + " split=r" + trial_rank[1].to_s() + "/d" + trial_bits[1].to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64
arm = 0
while arm < 2
  label = "median"
  if arm == 1
    label = "split"
  distance_avg = distance_sum[arm] / trials ## i64
  << "GF2_DEPENDENCY_ARM " + label + " returns=" + returns[arm].to_s() + " rank_wins=" + rank_wins[arm].to_s() + " density_wins=" + density_wins[arm].to_s() + " novel=" + novel[arm].to_s() + " distance_avg=" + distance_avg.to_s() + " best=r" + best_rank[arm].to_s() + "/d" + best_bits[arm].to_s()
  arm += 1
aggregate_moves = trials * moves * 2 ## i64
<< "GF2_DEPENDENCY_MATCH beats=" + median_beats.to_s() + "/" + split_beats.to_s() + " ties=" + ties.to_s()
<< "GF2_DEPENDENCY_SUMMARY trials=" + trials.to_s() + " moves=" + moves.to_s() + " aggregate=" + aggregate_moves.to_s() + " ms=" + elapsed.to_s()
