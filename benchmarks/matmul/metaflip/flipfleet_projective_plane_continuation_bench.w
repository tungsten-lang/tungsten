# Matched fertility test for the real 5x5 and 7x7 Fano-plane neutral endpoints.
#
# Three exact rank-93 presentations receive identical worker seeds/budgets:
#   source       checked-in d1155 archive,
#   projective   pinned quadrilateral endpoint at distance six/eight,
#   pair         one accepted ordinary pair flip from source.
#
# Usage:
#   flipfleet_projective_plane_continuation_bench [trials] [moves_per_arm] [5|7]

use flipfleet_projective_plane

-> ffppcb_expect(label, condition) (String bool) i64
  if !condition
    << "PROJECTIVE_PLANE_CONTINUATION_FAIL " + label
    exit(1)
  1

-> ffppcb_fingerprint_best(state) (i64[]) i64
  fingerprint = 0 ## i64
  i = 0 ## i64
  while i < ffw_best_rank(state)
    fingerprint = fingerprint ^ ffw_term_zobrist(ffw_read_best_u(state,i),ffw_read_best_v(state,i),ffw_read_best_w(state,i))
    i += 1
  fingerprint

-> ffppcb_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    result += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  result

-> ffppcb_make_projective(source_path, output_path, n, expected_rank, plane_axis, points, max_cells, expected_count, expected_distance, expected_mask) (String String i64 i64 i64 i64[] i64 i64 i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source,source_path,n,capacity,991001,0,1,1,1) ## i64
  if rank != expected_rank || ffw_verify_current_exact(source,n) != 1
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source,us,vs,ws) != rank
    return 0
  if ffpp_count_circuits(points) != 7
    return 0
  selected = i64[capacity]
  su = i64[capacity]
  sv = i64[capacity]
  sw = i64[capacity]
  count = ffpp_capture_plane(us,vs,ws,rank,plane_axis,points,selected,su,sv,sw) ## i64
  if count != expected_count
    return 0
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  meta = i64[16]
  made = ffpp_optimize_group(su,sv,sw,count,plane_axis,points,max_cells,out_u,out_v,out_w,meta) ## i64
  if made != expected_count || meta[5] != expected_count || meta[6] != expected_count || meta[7] != expected_mask || meta[12] != expected_distance
    return 0
  endpoint = i64[ffw_state_size(capacity)]
  endpoint_rank = ffmp_splice_state(source,selected,count,out_u,out_v,out_w,made,endpoint,991003) ## i64
  if endpoint_rank != rank || ffw_verify_current_exact(endpoint,n) != 1
    return 0
  ffw_dump_current(endpoint,output_path)

-> ffppcb_make_pair(source_path, output_path, n, expected_rank) (String String i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source,source_path,n,capacity,992001,4,4,1000000,250000) ## i64
  if rank != expected_rank || ffw_verify_current_exact(source,n) != 1
    return 0
  accepted = ffw_accepted(source) ## i64
  attempt = 0 ## i64
  while attempt < 100000 && ffw_accepted(source) == accepted
    z = ffw_try_flip(source,0) ## i64
    attempt += 1
  if ffw_accepted(source) == accepted || ffw_current_rank(source) != rank || ffw_verify_current_exact(source,n) != 1
    return 0
  ffw_dump_current(source,output_path)

args = argv()
trials = 16 ## i64
moves = 10000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
tensor_n = 5 ## i64
if args.size() > 2
  tensor_n = args[2].to_i()
if trials < 1 || trials > 64 || moves < 1 || moves > 2000000000 || (tensor_n != 5 && tensor_n != 7)
  << "usage: flipfleet_projective_plane_continuation_bench [trials:1..64] [moves_per_arm] [5|7]"
  exit(2)

source_path = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt" ## String
expected_rank = 93 ## i64
plane_axis = 2 ## i64
expected_count = 7 ## i64
expected_distance = 6 ## i64
expected_mask = 45 ## i64
max_cells = 16 ## i64
points = i64[7]
points[0] = 13325
points[1] = 21525
points[2] = 24600
points[3] = 22708245
points[4] = 22721560
points[5] = 22729728
points[6] = 22732813
if tensor_n == 7
  source_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt"
  expected_rank = 247
  plane_axis = 1
  expected_count = 5
  expected_distance = 8
  expected_mask = 75
  points[0] = 137439019008
  points[1] = 274878038016
  points[2] = 412317057024
  points[3] = 549756076032
  points[4] = 687195095040
  points[5] = 824634114048
  points[6] = 962073133056
projective_path = "/tmp/flipfleet_projective_plane_continuation_endpoint.out" ## String
pair_path = "/tmp/flipfleet_projective_plane_continuation_pair.out" ## String
ffppcb_expect("projective seed generated",ffppcb_make_projective(source_path,projective_path,tensor_n,expected_rank,plane_axis,points,max_cells,expected_count,expected_distance,expected_mask) == expected_rank)
ffppcb_expect("ordinary pair seed generated",ffppcb_make_pair(source_path,pair_path,tensor_n,expected_rank) == expected_rank)

capacity = ffw_default_capacity(tensor_n) ## i64
seed_paths = [source_path,projective_path,pair_path]
seed_labels = ["source","projective","pair"]
seed_density = i64[3]
seed_distance = i64[3]
seed_u = i64[capacity*3]
seed_v = i64[capacity*3]
seed_w = i64[capacity*3]
source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
arm = 0 ## i64
while arm < 3
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_load_scheme_cap(state,seed_paths[arm],tensor_n,capacity,993001+arm,0,1,1,1) ## i64
  ffppcb_expect("seed exact " + seed_labels[arm],loaded == expected_rank && ffw_verify_current_exact(state,tensor_n) == 1)
  local_u = i64[capacity]
  local_v = i64[capacity]
  local_w = i64[capacity]
  ffw_export_current(state,local_u,local_v,local_w)
  i = 0 ## i64
  while i < loaded
    seed_u[arm*capacity+i] = local_u[i]
    seed_v[arm*capacity+i] = local_v[i]
    seed_w[arm*capacity+i] = local_w[i]
    if arm == 0
      source_u[i] = local_u[i]
      source_v[i] = local_v[i]
      source_w[i] = local_w[i]
    i += 1
  seed_density[arm] = ffppcb_density(local_u,local_v,local_w,loaded)
  arm += 1
arm = 0
while arm < 3
  local_u = i64[capacity]
  local_v = i64[capacity]
  local_w = i64[capacity]
  i = 0 ## i64
  while i < expected_rank
    local_u[i] = seed_u[arm*capacity+i]
    local_v[i] = seed_v[arm*capacity+i]
    local_w[i] = seed_w[arm*capacity+i]
    i += 1
  seed_distance[arm] = ffmp_term_set_distance(source_u,source_v,source_w,expected_rank,local_u,local_v,local_w,expected_rank)
  arm += 1
ffppcb_expect("projective distance",seed_distance[1] == expected_distance)
ffppcb_expect("pair distance",seed_distance[2] == 4)

rank_wins = i64[3]
density_wins = i64[3]
best_rank = i64[3]
best_bits = i64[3]
best_updates = i64[3]
accepted = i64[3]
rejected = i64[3]
rank_drops = i64[3]
distinct = i64[3]
arm = 0
while arm < 3
  best_rank[arm] = 1000
  best_bits[arm] = 9223372036854775807
  arm += 1
projective_beats_source = 0 ## i64
source_beats_projective = 0 ## i64
ties = 0 ## i64
fingerprints = i64[trials*3]
started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  trial_rank = i64[3]
  trial_bits = i64[3]
  arm = 0
  while arm < 3
    state = i64[ffw_state_size(capacity)]
    seed = 994001 + trial*104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = ffw_load_scheme_cap(state,seed_paths[arm],tensor_n,capacity,seed,4,4,workq,wanderq) ## i64
    ffppcb_expect("matched arm load",loaded == expected_rank)
    z = ffw_walk(state,moves) ## i64
    ffppcb_expect("matched arm exact",ffw_verify_best_exact(state,tensor_n) == 1)
    trial_rank[arm] = ffw_best_rank(state)
    trial_bits[arm] = ffw_best_bits(state)
    if trial_rank[arm] < expected_rank
      rank_wins[arm] += 1
    if trial_rank[arm] == expected_rank && trial_bits[arm] < seed_density[arm]
      density_wins[arm] += 1
    if trial_rank[arm] < best_rank[arm] || (trial_rank[arm] == best_rank[arm] && trial_bits[arm] < best_bits[arm])
      best_rank[arm] = trial_rank[arm]
      best_bits[arm] = trial_bits[arm]
    best_updates[arm] += ffw_best_updates(state)
    accepted[arm] += ffw_accepted(state)
    rejected[arm] += ffw_rejected(state)
    rank_drops[arm] += ffw_rank_drops(state)
    fingerprint = ffppcb_fingerprint_best(state) ## i64
    fingerprints[arm*trials+trial] = fingerprint
    already = 0 ## i64
    prior = 0 ## i64
    while prior < trial
      if fingerprints[arm*trials+prior] == fingerprint
        already = 1
      prior += 1
    if already == 0
      distinct[arm] += 1
    arm += 1
  if trial_rank[1] < trial_rank[0] || (trial_rank[1] == trial_rank[0] && trial_bits[1] < trial_bits[0])
    projective_beats_source += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    source_beats_projective += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64

arm = 0
while arm < 3
  << "PROJECTIVE_PLANE_CONTINUATION tensor=" + tensor_n.to_s() + "x" + tensor_n.to_s() + " arm=" + seed_labels[arm] + " seed=r" + expected_rank.to_s() + "/d" + seed_density[arm].to_s() + " distance=" + seed_distance[arm].to_s() + " trials=" + trials.to_s() + " moves_each=" + moves.to_s() + " rank_wins=" + rank_wins[arm].to_s() + " density_wins=" + density_wins[arm].to_s() + " best=r" + best_rank[arm].to_s() + "/d" + best_bits[arm].to_s() + " best_updates=" + best_updates[arm].to_s() + " accepted=" + accepted[arm].to_s() + " rejected=" + rejected[arm].to_s() + " rank_drops=" + rank_drops[arm].to_s() + " distinct_endpoints=" + distinct[arm].to_s()
  arm += 1
<< "PROJECTIVE_PLANE_CONTINUATION_MATCHED projective_beats_source=" + projective_beats_source.to_s() + " source_beats_projective=" + source_beats_projective.to_s() + " ties=" + ties.to_s() + " aggregate_moves=" + (trials*moves*3).to_s() + " elapsed_ms=" + elapsed.to_s()
if !system("/bin/rm -f " + projective_path + " " + pair_path)
  << "PROJECTIVE_PLANE_CONTINUATION_WARN cleanup failed"
<< "flipfleet_projective_plane_continuation_bench: pass"
