# Bounded effectiveness audit for the square 7x7 CPU restart doors.
#
#   seven_by_seven_cpu_role_bench [moves-per-trial] [trials]
#
# Every trial starts from a production-exact seed, runs the ordinary walker,
# and independently gates the final current tensor.  The report distinguishes
# proposal acceptance (cheap motion) from useful rank closure and exact basin
# novelty.  It is intentionally a decision benchmark, not a unit test: record
# improvements are rare, while a role that never moves or never leaves its
# source identity is immediately visible.

use ../lib/metaflip/scheme
use ../lib/metaflip/seeds/catalog
use ../lib/metaflip/fleet/archive
use ../lib/metaflip/fleet/basins
use ../lib/metaflip/fleet/frontier

-> s7crb_contains(values, value) i64
  i = 0 ## i64
  while i < values.size()
    if values[i] == value
      return 1
    i += 1
  0

-> s7crb_current_snapshot(state, output, us, vs, ws, n, capacity, seed, workq, wanderq) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  rank = ffw_export_current(state, us, vs, ws) ## i64
  if rank < 1
    return 0
  loaded = ffw_init_terms_cap(output, us, vs, ws, rank, n, capacity, seed, 8, 7, workq, wanderq) ## i64
  if loaded != rank || ffw_verify_best_exact(output, n) != 1
    return 0
  loaded

-> s7crb_min_frontier_distance(candidate, frontier) i64
  minimum = 999999999 ## i64
  i = 0 ## i64
  while i < frontier.size()
    distance = ffn_distance(candidate, frontier[i]) ## i64
    if distance < minimum
      minimum = distance
    i += 1
  minimum

-> s7crb_run(label, pool, frontier, leader_rank, leader_bits, n, capacity, state_size, moves, trials, seed_base) i64
  if pool.size() == 0
    << "CPU_ROLE role=" + label + " unavailable=1"
    return 0
  proposals = 0 ## i64
  accepted = 0 ## i64
  rejected = 0 ## i64
  misses = 0 ## i64
  best_updates = 0 ## i64
  rank_closures = 0 ## i64
  rank_drop_sum = 0 ## i64
  density_wins = 0 ## i64
  same_rank_density_trials = 0 ## i64
  same_rank_density_gain = 0 ## i64
  frontier_density_delta = 0 ## i64
  exact_endpoints = 0 ## i64
  novel_endpoints = 0 ## i64
  frontier_novel = 0 ## i64
  endpoint_ids = []
  min_distance = 999999999 ## i64
  max_distance = 0 ## i64
  total_seed_debt = 0 ## i64
  total_final_debt = 0 ## i64
  total_best_bits = 0 ## i64
  total_ns = 0 ## i64
  trial = 0 ## i64
  while trial < trials
    source_index = (trial * 7 + seed_base) % pool.size() ## i64
    source = pool[source_index]
    state = i64[state_size]
    cloned = ffw_reseed_from(state, source, seed_base * 1009 + trial * 7919 + 17) ## i64
    if cloned < 1
      << "FAIL CPU_ROLE clone role=" + label + " trial=" + trial.to_s()
      exit(1)
    # Balanced quotas match the wide-host extra-lane baseline.  The measured
    # tranche is deliberately shorter than a production lease, so all roles
    # are compared in the same work-zone phase rather than at different band
    # boundaries.
    z = ffw_set_zone_quotas(state, 1000000000, 200000000) ## i64
    seed_rank = ffw_best_rank(source) ## i64
    seed_bits = ffw_best_bits(source) ## i64
    total_seed_debt += seed_rank - leader_rank
    started = ccall_nobox("__w_clock_ns_raw") ## i64
    walked = ffw_walk(state, moves) ## i64
    elapsed = ccall_nobox("__w_clock_ns_raw") - started ## i64
    if elapsed < 1
      elapsed = 1
    total_ns += elapsed
    proposals += ffw_proposals(state)
    accepted += ffw_accepted(state)
    rejected += ffw_rejected(state)
    misses += ffw_partner_misses(state)
    best_updates += ffw_best_updates(state)
    final_rank = ffw_best_rank(state) ## i64
    final_bits = ffw_best_bits(state) ## i64
    total_final_debt += final_rank - leader_rank
    total_best_bits += final_bits
    if seed_rank > leader_rank && final_rank <= leader_rank
      rank_closures += 1
    if final_rank < seed_rank
      rank_drop_sum += seed_rank - final_rank
    if final_rank == seed_rank && final_bits < seed_bits
      same_rank_density_trials += 1
      same_rank_density_gain += seed_bits - final_bits
    if final_rank == leader_rank
      frontier_density_delta += final_bits - leader_bits
    if final_rank < leader_rank || (final_rank == leader_rank && final_bits < leader_bits)
      density_wins += 1
    if walked != final_rank || ffw_verify_current_exact(state, n) != 1
      << "FAIL CPU_ROLE exact role=" + label + " trial=" + trial.to_s()
      exit(1)
    exact_endpoints += 1
    snapshot = i64[state_size]
    us = i64[capacity]
    vs = i64[capacity]
    ws = i64[capacity]
    snapshot_rank = s7crb_current_snapshot(state, snapshot, us, vs, ws, n, capacity, seed_base + trial * 17, 1000000000, 200000000) ## i64
    if snapshot_rank < 1
      << "FAIL CPU_ROLE snapshot role=" + label + " trial=" + trial.to_s()
      exit(1)
    endpoint_id = ffbi_best_id(snapshot) ## i64
    if s7crb_contains(endpoint_ids, endpoint_id) == 0
      endpoint_ids.push(endpoint_id)
    source_distance = ffn_distance(snapshot, source) ## i64
    if source_distance > 0
      novel_endpoints += 1
    if source_distance < min_distance
      min_distance = source_distance
    if source_distance > max_distance
      max_distance = source_distance
    frontier_distance = s7crb_min_frontier_distance(snapshot, frontier) ## i64
    if snapshot_rank == leader_rank && frontier_distance >= 4
      frontier_novel += 1
    trial += 1
  if min_distance == 999999999
    min_distance = 0
  accept_ppm = 0 ## i64
  if proposals > 0
    accept_ppm = accepted * 1000000 / proposals
  inverse_ppm = 0 ## i64
  if accepted > 0
    # Partner misses are proposal failures, not accepted inverses.  Report
    # them separately so high acceptance cannot hide an unproductive support.
    inverse_ppm = misses * 1000000 / proposals
  rate_milli_mps = moves * trials * 1000000 / total_ns ## i64
  << "CPU_ROLE role=" + label + " seeds=" + pool.size().to_s() + " trials=" + trials.to_s() + " moves=" + (moves * trials).to_s() + " rate_milli_mps=" + rate_milli_mps.to_s() + " proposals=" + proposals.to_s() + " accepted=" + accepted.to_s() + " accept_ppm=" + accept_ppm.to_s() + " rejected=" + rejected.to_s() + " miss_ppm=" + inverse_ppm.to_s() + " updates=" + best_updates.to_s() + " seed_debt_sum=" + total_seed_debt.to_s() + " final_debt_sum=" + total_final_debt.to_s() + " rank_closures=" + rank_closures.to_s() + " rank_drop_sum=" + rank_drop_sum.to_s() + " density_trials=" + same_rank_density_trials.to_s() + " density_gain=" + same_rank_density_gain.to_s() + " frontier_density_delta=" + frontier_density_delta.to_s() + " record_wins=" + density_wins.to_s() + " exact=" + exact_endpoints.to_s() + " novel=" + novel_endpoints.to_s() + " unique=" + endpoint_ids.size().to_s() + " frontier_novel=" + frontier_novel.to_s() + " distance_min_max=" + min_distance.to_s() + "," + max_distance.to_s() + " best_bits_sum=" + total_best_bits.to_s()
  1

args = argv()
moves = 25000000 ## i64
trials = 4 ## i64
if args.size() > 0
  moves = args[0].to_i()
if args.size() > 1
  trials = args[1].to_i()
if moves < 1
  moves = 1
if trials < 1
  trials = 1

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
root = __DIR__ + "/../lib/metaflip/" ## String
workq = 1000000000 ## i64
wanderq = 200000000 ## i64

leader = i64[state_size]
leader_path = root + ffp_seed_path(n)
leader_rank = ffw_load_scheme_cap(leader, leader_path, n, capacity, 70001, 8, 7, workq, wanderq) ## i64
if leader_rank != 247 || ffw_verify_best_exact(leader, n) != 1
  << "FAIL CPU_ROLE leader"
  exit(1)
leader_bits = ffw_best_bits(leader) ## i64

leader_pool = []
leader_pool.push(leader)
anchor_pool = []
anchor_pool.push(leader)
symmetry_fallback_pool = []
symmetry_fallback_pool.push(leader)
frontier_pool = []
paths = ffp_frontier_seed_paths(n)
i = 0 ## i64
while i < paths.size()
  candidate = i64[state_size]
  rank = ffw_load_scheme_cap(candidate, root + paths[i], n, capacity, 71001 + i * 17, 8, 7, workq, wanderq) ## i64
  if rank == leader_rank && ffw_verify_best_exact(candidate, n) == 1
    frontier_pool.push(candidate)
  i += 1
if frontier_pool.size() < 2
  << "FAIL CPU_ROLE frontier inventory"
  exit(1)

near1_pool = []
near2_pool = []
mixed_pool = []
kind = 1 ## i64
while kind <= 5
  nonce = 0 ## i64
  while nonce < 6
    escaped = fffeb_escape_state(leader, kind, nonce, n, capacity, state_size, 72001 + kind * 97 + nonce, 8, 7, workq, wanderq)
    if escaped != nil && ffw_verify_best_exact(escaped, n) == 1
      mixed_pool.push(escaped)
      if ffw_best_rank(escaped) == leader_rank + 1
        near1_pool.push(escaped)
      if ffw_best_rank(escaped) == leader_rank + 2
        near2_pool.push(escaped)
    nonce += 1
  kind += 1

shoulder_names = ["matmul_7x7_rank248_d2952_sedoglavic_gf2.txt",
                  "matmul_7x7_rank248_d2958_sedoglavic_gf2.txt",
                  "matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt",
                  "matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt"]
i = 0
while i < shoulder_names.size()
  shoulder = i64[state_size]
  rank = ffw_load_scheme_cap(shoulder, root + "seeds/gf2/" + shoulder_names[i], n, capacity, 73001 + i * 17, 8, 7, workq, wanderq) ## i64
  if rank == leader_rank + 1 && ffw_verify_best_exact(shoulder, n) == 1
    near1_pool.push(shoulder)
  i += 1

if near1_pool.size() == 0 || near2_pool.size() == 0 || mixed_pool.size() == 0
  << "FAIL CPU_ROLE escape inventory near1=" + near1_pool.size().to_s() + " near2=" + near2_pool.size().to_s() + " mixed=" + mixed_pool.size().to_s()
  exit(1)

z = s7crb_run("leader", leader_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 1) ## i64
z = s7crb_run("frontier", frontier_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 2)
z = s7crb_run("near1", near1_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 3)
z = s7crb_run("near2", near2_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 4)
z = s7crb_run("symmetry-fallback", symmetry_fallback_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 5)
z = s7crb_run("mixed", mixed_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 6)
z = s7crb_run("anchor", anchor_pool, frontier_pool, leader_rank, leader_bits, n, capacity, state_size, moves, trials, 7)
<< "PASS 7x7 CPU role audit"
