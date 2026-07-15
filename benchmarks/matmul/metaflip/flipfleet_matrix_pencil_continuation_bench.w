# Matched downstream fertility test for the real 5x5 matrix-pencil tunnel.
#
# Three exact rank-93 presentations receive identical worker seeds/budgets:
#   source     checked-in d1155 archive,
#   pencil     the farthest exact k=5 whole-pencil endpoint,
#   pair       one accepted ordinary pair flip from source, serialized/reload.
#
# Usage: flipfleet_matrix_pencil_continuation_bench [trials] [moves_per_arm]

use flipfleet_matrix_pencil

-> ffmpcb_expect(label, condition) (String bool) i64
  if !condition
    << "MATRIX_PENCIL_CONTINUATION_FAIL " + label
    exit(1)
  1

-> ffmpcb_fingerprint_best(state) (i64[]) i64
  fingerprint = 0 ## i64
  i = 0 ## i64
  while i < ffw_best_rank(state)
    fingerprint = fingerprint ^ ffw_term_zobrist(ffw_read_best_u(state,i),ffw_read_best_v(state,i),ffw_read_best_w(state,i))
    i += 1
  fingerprint

-> ffmpcb_density(us, vs, ws, count) (i64[] i64[] i64[] i64) i64
  result = 0 ## i64
  i = 0 ## i64
  while i < count
    result += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  result

-> ffmpcb_make_pencil(source_path, output_path) (String String) i64
  n = 5 ## i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source,source_path,n,capacity,869001,0,1,1,1) ## i64
  if rank != 93 || ffw_verify_current_exact(source,n) != 1
    return 0
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(source,us,vs,ws) != rank
    return 0
  # This is the real axis-V five-term line from the d1155 archive.  The
  # generic audit discovers it; pinning it here keeps the continuation test
  # independent of any production-worker wrapper.
  line = i64[3]
  line[0] = 168965
  line[1] = 5248005
  line[2] = 5406720
  selected = i64[capacity]
  su = i64[capacity]
  sv = i64[capacity]
  sw = i64[capacity]
  count = ffmp_capture_line(us,vs,ws,rank,1,line,selected,su,sv,sw) ## i64
  if count != 5
    return 0
  no_table = i32[1]
  out_u = i64[32]
  out_v = i64[32]
  out_w = i64[32]
  meta = i64[14]
  made = ffmp_optimize_group(su,sv,sw,count,1,line,20,no_table,out_u,out_v,out_w,meta) ## i64
  if made != 5 || meta[5] != 5 || meta[6] != 5 || meta[12] < 8
    return 0
  endpoint = i64[ffw_state_size(capacity)]
  endpoint_rank = ffmp_splice_state(source,selected,count,out_u,out_v,out_w,made,endpoint,869003) ## i64
  if endpoint_rank != rank || ffw_verify_current_exact(endpoint,n) != 1
    return 0
  ffw_dump_current(endpoint,output_path)

-> ffmpcb_make_pair(source_path, output_path) (String String) i64
  n = 5 ## i64
  capacity = ffw_default_capacity(n) ## i64
  source = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(source,source_path,n,capacity,870001,4,4,1000000,250000) ## i64
  if rank != 93 || ffw_verify_current_exact(source,n) != 1
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
trials = 12 ## i64
moves = 25000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
if trials < 1 || trials > 64 || moves < 1 || moves > 2000000000
  << "usage: flipfleet_matrix_pencil_continuation_bench [trials:1..64] [moves_per_arm]"
  exit(2)

source_path = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt" ## String
pencil_path = "/tmp/flipfleet_matrix_pencil_continuation_pencil.out" ## String
pair_path = "/tmp/flipfleet_matrix_pencil_continuation_pair.out" ## String
ffmpcb_expect("pencil seed generated",ffmpcb_make_pencil(source_path,pencil_path) == 93)
ffmpcb_expect("ordinary pair seed generated",ffmpcb_make_pair(source_path,pair_path) == 93)

capacity = ffw_default_capacity(5) ## i64
seed_paths = [source_path,pencil_path,pair_path]
seed_labels = ["source","pencil","pair"]
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
  loaded = ffw_load_scheme_cap(state,seed_paths[arm],5,capacity,871001+arm,0,1,1,1) ## i64
  ffmpcb_expect("seed exact " + seed_labels[arm],loaded == 93 && ffw_verify_current_exact(state,5) == 1)
  local_u = i64[capacity]
  local_v = i64[capacity]
  local_w = i64[capacity]
  ffw_export_current(state,local_u,local_v,local_w)
  i = 0 ## i64
  while i < loaded
    seed_u[arm*capacity+i] = local_u[i]
    seed_v[arm*capacity+i] = local_v[i]
    seed_w[arm*capacity+i] = local_w[i]
    i += 1
  seed_density[arm] = ffmpcb_density(local_u,local_v,local_w,loaded)
  if arm == 0
    i = 0
    while i < loaded
      source_u[i] = local_u[i]
      source_v[i] = local_v[i]
      source_w[i] = local_w[i]
      i += 1
  arm += 1
arm = 0
while arm < 3
  local_u = i64[capacity]
  local_v = i64[capacity]
  local_w = i64[capacity]
  i = 0 ## i64
  while i < 93
    local_u[i] = seed_u[arm*capacity+i]
    local_v[i] = seed_v[arm*capacity+i]
    local_w[i] = seed_w[arm*capacity+i]
    i += 1
  seed_distance[arm] = ffmp_term_set_distance(source_u,source_v,source_w,93,local_u,local_v,local_w,93)
  arm += 1
ffmpcb_expect("pencil starts beyond one pair",seed_distance[1] >= 8)
ffmpcb_expect("pair control is one pair",seed_distance[2] == 4)

rank_wins = i64[3]
density_wins = i64[3]
best_rank = i64[3]
best_bits = i64[3]
best_updates = i64[3]
accepted = i64[3]
rejected = i64[3]
rank_drops = i64[3]
distinct = i64[3]
best_rank[0] = 1000
best_rank[1] = 1000
best_rank[2] = 1000
best_bits[0] = 9223372036854775807
best_bits[1] = 9223372036854775807
best_bits[2] = 9223372036854775807
pencil_beats_source = 0 ## i64
source_beats_pencil = 0 ## i64
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
    seed = 880001 + trial*104729 ## i64
    workq = moves / 2 ## i64
    wanderq = moves / 8 ## i64
    if workq < 1
      workq = 1
    if wanderq < 1
      wanderq = 1
    loaded = ffw_load_scheme_cap(state,seed_paths[arm],5,capacity,seed,4,4,workq,wanderq) ## i64
    ffmpcb_expect("matched arm load",loaded == 93)
    z = ffw_walk(state,moves) ## i64
    ffmpcb_expect("matched arm exact",ffw_verify_best_exact(state,5) == 1)
    trial_rank[arm] = ffw_best_rank(state)
    trial_bits[arm] = ffw_best_bits(state)
    if trial_rank[arm] < 93
      rank_wins[arm] += 1
    if trial_rank[arm] == 93 && trial_bits[arm] < seed_density[arm]
      density_wins[arm] += 1
    if trial_rank[arm] < best_rank[arm] || (trial_rank[arm] == best_rank[arm] && trial_bits[arm] < best_bits[arm])
      best_rank[arm] = trial_rank[arm]
      best_bits[arm] = trial_bits[arm]
    best_updates[arm] += ffw_best_updates(state)
    accepted[arm] += ffw_accepted(state)
    rejected[arm] += ffw_rejected(state)
    rank_drops[arm] += ffw_rank_drops(state)
    fingerprint = ffmpcb_fingerprint_best(state) ## i64
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
    pencil_beats_source += 1
  if trial_rank[0] < trial_rank[1] || (trial_rank[0] == trial_rank[1] && trial_bits[0] < trial_bits[1])
    source_beats_pencil += 1
  if trial_rank[0] == trial_rank[1] && trial_bits[0] == trial_bits[1]
    ties += 1
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64

arm = 0
while arm < 3
  << "MATRIX_PENCIL_CONTINUATION arm=" + seed_labels[arm] + " seed=r93/d" + seed_density[arm].to_s() + " distance=" + seed_distance[arm].to_s() + " trials=" + trials.to_s() + " moves_each=" + moves.to_s() + " rank_wins=" + rank_wins[arm].to_s() + " density_wins=" + density_wins[arm].to_s() + " best=r" + best_rank[arm].to_s() + "/d" + best_bits[arm].to_s() + " best_updates=" + best_updates[arm].to_s() + " accepted=" + accepted[arm].to_s() + " rejected=" + rejected[arm].to_s() + " rank_drops=" + rank_drops[arm].to_s() + " distinct_endpoints=" + distinct[arm].to_s()
  arm += 1
<< "MATRIX_PENCIL_CONTINUATION_MATCHED pencil_beats_source=" + pencil_beats_source.to_s() + " source_beats_pencil=" + source_beats_pencil.to_s() + " ties=" + ties.to_s() + " aggregate_moves=" + (trials*moves*3).to_s() + " elapsed_ms=" + elapsed.to_s()
if !system("/bin/rm -f " + pencil_path + " " + pair_path)
  << "MATRIX_PENCIL_CONTINUATION_WARN cleanup failed"
<< "flipfleet_matrix_pencil_continuation_bench: pass"
