# Equal-move fertility control for the bounded 7x7 whole-bucket +1 shoulder
# against an ordinary exact +1 split from the same rank-247 source.

use flipfleet_projective_bucket5
use flipfleet_global_isotropy
use flipfleet_escape

-> ffpb5cb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_BUCKET5_CONTINUATION_FAIL " + label
    exit(1)
  1

args = argv()
trials = 12 ## i64
moves = 10000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
ffpb5cb_expect("arguments",trials >= 1 && trials <= 64 && moves >= 1 && moves <= 2000000000)

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base,"benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt",n,capacity,985001,4,4,500000,100000) ## i64
ffpb5cb_expect("base",base_rank == 247 && ffw_current_bits(base) == 3554 && ffw_verify_current_exact(base,n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffpb5cb_expect("base export",ffw_export_current(base,base_u,base_v,base_w) == base_rank)

bucket_state = i64[state_size]
bucket_meta = i64[30]
bucket_rank = ffpb5_search_state(base,2048,1,7,bucket_state,bucket_meta) ## i64
ffpb5cb_expect("bucket shoulder",bucket_rank == 248 && bucket_meta[24] == 1 && ffw_verify_current_exact(bucket_state,n) == 1)
bucket_u = i64[capacity]
bucket_v = i64[capacity]
bucket_w = i64[capacity]
ffpb5cb_expect("bucket export",ffw_export_current(bucket_state,bucket_u,bucket_v,bucket_w) == bucket_rank)

bucket_returns = 0 ## i64
split_returns = 0 ## i64
bucket_rank_wins = 0 ## i64
split_rank_wins = 0 ## i64
bucket_density_wins = 0 ## i64
split_density_wins = 0 ## i64
bucket_novel = 0 ## i64
split_novel = 0 ## i64
bucket_distance_sum = 0 ## i64
split_distance_sum = 0 ## i64
bucket_best_rank = 1000 ## i64
split_best_rank = 1000 ## i64
bucket_best_bits = 9223372036854775807 ## i64
split_best_bits = 9223372036854775807 ## i64
bucket_beats = 0 ## i64
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
  while attempt < base_rank * 3 && split_rank != 248
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
  ffpb5cb_expect("split shoulder",split_rank == 248)
  split_gate = i64[state_size]
  ffpb5cb_expect("split exact",ffw_init_terms_cap(split_gate,split_u,split_v,split_w,split_rank,n,capacity,986001 + trial,4,4,500000,100000) == 248 && ffw_verify_current_exact(split_gate,n) == 1)

  trial_rank = i64[2]
  trial_bits = i64[2]
  arm = 0 ## i64
  while arm < 2
    state = i64[state_size]
    walk_seed = 987001 + trial * 104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = 0 ## i64
    if arm == 0
      loaded = ffw_init_terms_cap(state,bucket_u,bucket_v,bucket_w,bucket_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    else
      loaded = ffw_init_terms_cap(state,split_u,split_v,split_w,split_rank,n,capacity,walk_seed,4,4,workq,wanderq)
    ffpb5cb_expect("walk init",loaded == 248)
    z = ffw_walk(state,moves) ## i64
    ffpb5cb_expect("walk exact",ffw_verify_best_exact(state,n) == 1)
    trial_rank[arm] = ffw_best_rank(state)
    trial_bits[arm] = ffw_best_bits(state)
    endpoint_u = i64[capacity]
    endpoint_v = i64[capacity]
    endpoint_w = i64[capacity]
    z = ffw_export_best(state,endpoint_u,endpoint_v,endpoint_w)
    distance = ffgir_term_set_distance(base_u,base_v,base_w,base_rank,endpoint_u,endpoint_v,endpoint_w,trial_rank[arm]) ## i64
    if arm == 0
      if trial_rank[arm] <= base_rank
        bucket_returns += 1
      if trial_rank[arm] < base_rank
        bucket_rank_wins += 1
      if trial_rank[arm] == base_rank && trial_bits[arm] < 3554
        bucket_density_wins += 1
      if trial_rank[arm] < bucket_best_rank || (trial_rank[arm] == bucket_best_rank && trial_bits[arm] < bucket_best_bits)
        bucket_best_rank = trial_rank[arm]
        bucket_best_bits = trial_bits[arm]
      bucket_distance_sum += distance
      if trial_rank[arm] == base_rank && distance > 0
        bucket_novel += 1
    else
      if trial_rank[arm] <= base_rank
        split_returns += 1
      if trial_rank[arm] < base_rank
        split_rank_wins += 1
      if trial_rank[arm] == base_rank && trial_bits[arm] < 3554
        split_density_wins += 1
      if trial_rank[arm] < split_best_rank || (trial_rank[arm] == split_best_rank && trial_bits[arm] < split_best_bits)
        split_best_rank = trial_rank[arm]
        split_best_bits = trial_bits[arm]
      split_distance_sum += distance
      if trial_rank[arm] == base_rank && distance > 0
        split_novel += 1
    arm += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    bucket_beats += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[0] == trial_rank[1] && trial_bits[1] < trial_bits[0])
    split_beats += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  << "PROJECTIVE_BUCKET5_CONTINUATION trial=" + trial.to_s() + " bucket=r" + trial_rank[0].to_s() + "/d" + trial_bits[0].to_s() + " split=r" + trial_rank[1].to_s() + "/d" + trial_bits[1].to_s()
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64
bucket_distance_avg = bucket_distance_sum / trials ## i64
split_distance_avg = split_distance_sum / trials ## i64
aggregate_moves = trials * moves * 2 ## i64
<< "PROJECTIVE_BUCKET5_ARM bucket returns=" + bucket_returns.to_s() + " rank_wins=" + bucket_rank_wins.to_s() + " density_wins=" + bucket_density_wins.to_s() + " novel=" + bucket_novel.to_s() + " distance_avg=" + bucket_distance_avg.to_s() + " best=r" + bucket_best_rank.to_s() + "/d" + bucket_best_bits.to_s()
<< "PROJECTIVE_BUCKET5_ARM split returns=" + split_returns.to_s() + " rank_wins=" + split_rank_wins.to_s() + " density_wins=" + split_density_wins.to_s() + " novel=" + split_novel.to_s() + " distance_avg=" + split_distance_avg.to_s() + " best=r" + split_best_rank.to_s() + "/d" + split_best_bits.to_s()
<< "PROJECTIVE_BUCKET5_MATCH beats=" + bucket_beats.to_s() + "/" + split_beats.to_s() + " ties=" + ties.to_s()
<< "PROJECTIVE_BUCKET5_SUMMARY trials=" + trials.to_s() + " moves=" + moves.to_s() + " aggregate=" + aggregate_moves.to_s() + " ms=" + elapsed.to_s()
