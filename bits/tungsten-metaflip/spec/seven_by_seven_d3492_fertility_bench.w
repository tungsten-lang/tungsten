use ../lib/metaflip/fleet/archive
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/scheme

# Historical reproducibility check for the C013 density door. The d3492 CUDA
# child is only four support terms from the d3496 fixed-pocket closure. Both
# are now explicit provenance for the stronger d3486 continuation endpoint,
# so this benchmark retains the matched comparison without claiming either
# historical source is still active.

-> ff7df_contains(paths, wanted)
  i = 0 ## i64
  while i < paths.size()
    if paths[i] == wanted
      return 1
    i += 1
  0

trials = 24 ## i64
steps = 1000000 ## i64
if ARGV.size() > 0
  trials = ARGV[0].to_i()
if ARGV.size() > 1
  steps = ARGV[1].to_i()
if trials < 1 || trials > 10000 || steps < 1
  << "D3492_FERTILITY_FAIL invalid-budget"
  exit(2)

runtime_root = __DIR__ + "/../lib/metaflip/"
prefix = "seeds/gf2/"
d3492_name = "matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt"
d3496_name = "matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt"
d3486_name = "matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt"
leader_name = "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64
d3492 = i64[state_size]
d3496 = i64[state_size]
leader = i64[state_size]
r3492 = ffw_load_scheme_cap(d3492, runtime_root + prefix + d3492_name, 7, capacity, 349201, 4, 1, steps, steps / 4) ## i64
r3496 = ffw_load_scheme_cap(d3496, runtime_root + prefix + d3496_name, 7, capacity, 349203, 4, 1, steps, steps / 4) ## i64
rleader = ffw_load_scheme_cap(leader, runtime_root + prefix + leader_name, 7, capacity, 349205, 4, 1, steps, steps / 4) ## i64
if r3492 != 247 || r3496 != 247 || rleader != 247 || ffw_best_bits(d3492) != 3492 || ffw_best_bits(d3496) != 3496 || ffw_best_bits(leader) != 3094
  << "D3492_FERTILITY_FAIL load-or-density"
  exit(1)
if ffw_verify_best_exact(d3492, 7) != 1 || ffw_verify_best_exact(d3496, 7) != 1 || ffw_verify_best_exact(leader, 7) != 1
  << "D3492_FERTILITY_FAIL exact"
  exit(1)
if ffn_distance(d3492, d3496) != 4 || ffn_distance(d3492, leader) != 494
  << "D3492_FERTILITY_FAIL distance"
  exit(1)

rediscovery_distance = 0 - 1 ## i64
if ARGV.size() > 2
  rediscovery = i64[state_size]
  rediscovery_rank = ffw_load_scheme_cap(rediscovery, ARGV[2], 7, capacity, 349207, 4, 1, steps, steps / 4) ## i64
  rediscovery_distance = ffn_distance(rediscovery, d3492)
  if rediscovery_rank != 247 || ffw_best_bits(rediscovery) != 3492 || ffw_verify_best_exact(rediscovery, 7) != 1 || rediscovery_distance != 0
    << "D3492_FERTILITY_FAIL rediscovery"
    exit(1)

active = ffp_frontier_seed_paths(7)
explicit = ffp_experimental_seed_paths(7)
if ff7df_contains(active, prefix + d3486_name) != 1 || ff7df_contains(active, prefix + d3492_name) != 0 || ff7df_contains(active, prefix + d3496_name) != 0 || ff7df_contains(explicit, prefix + d3492_name) != 1 || ff7df_contains(explicit, prefix + d3496_name) != 1
  << "D3492_FERTILITY_FAIL catalog"
  exit(1)

left_wins = 0 ## i64
right_wins = 0 ## i64
ties = 0 ## i64
left_sum = 0 ## i64
right_sum = 0 ## i64
left_min = 999999999 ## i64
right_min = 999999999 ## i64
started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  seed = 300001 + trial * 104729 ## i64
  left = i64[state_size]
  right = i64[state_size]
  if ffw_reseed_from(left, d3492, seed) != 247 || ffw_reseed_from(right, d3496, seed) != 247
    << "D3492_FERTILITY_FAIL reseed"
    exit(1)
  ffw_walk(left, steps)
  ffw_walk(right, steps)
  if ffw_verify_best_exact(left, 7) != 1 || ffw_verify_best_exact(right, 7) != 1
    << "D3492_FERTILITY_FAIL continuation-exact"
    exit(1)
  lb = ffw_best_bits(left) ## i64
  rb = ffw_best_bits(right) ## i64
  left_sum += lb
  right_sum += rb
  if lb < left_min
    left_min = lb
  if rb < right_min
    right_min = rb
  if ffw_best_rank(left) < ffw_best_rank(right) || (ffw_best_rank(left) == ffw_best_rank(right) && lb < rb)
    left_wins += 1
  elsif ffw_best_rank(right) < ffw_best_rank(left) || (ffw_best_rank(right) == ffw_best_rank(left) && rb < lb)
    right_wins += 1
  else
    ties += 1
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64

if trials == 24 && steps == 1000000 && (left_wins != 20 || right_wins != 0 || ties != 4 || left_min != 3492 || right_min != 3492 || left_sum / trials != 3492 || right_sum / trials != 3495)
  << "D3492_FERTILITY_FAIL default-fixture wins=" + left_wins.to_s() + "/" + right_wins.to_s() + "/" + ties.to_s()
  exit(1)

<< "D3492_FERTILITY_PASS trials=" + trials.to_s() + " steps=" + steps.to_s() + " wins-d3492/d3496/tie=" + left_wins.to_s() + "/" + right_wins.to_s() + "/" + ties.to_s() + " start=3492/3496 min=" + left_min.to_s() + "/" + right_min.to_s() + " avg=" + (left_sum / trials).to_s() + "/" + (right_sum / trials).to_s() + " support-gap=4 leader-gap=494 rediscovery-gap=" + rediscovery_distance.to_s() + " elapsed-ms=" + elapsed.to_s()
