use flipfleet_fixed_rank_pocket
use flipfleet_bank_policy

-> fffrpcb_expect(label, condition) (String bool) i64
  if !condition
    << "FIXED_RANK_POCKET_CONTINUATION_FAIL " + label
    exit(1)
  1

-> fffrpcb_state(scheme, seed) (FFBCScheme i64)
  if scheme == nil
    return nil
  rank = scheme.rank() ## i64
  capacity = ffw_default_capacity(7) ## i64
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if fffrp_scalar_scheme(scheme, us, vs, ws) != rank
    return nil
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, us, vs, ws, rank, 7, capacity, seed, 4, 1, 25000000, 6250000) ## i64
  if loaded != rank || ffw_verify_best_exact(state, 7) != 1
    return nil
  state

-> fffrpcb_better(left, right) (i64[] i64[]) i64
  if ffw_best_rank(left) < ffw_best_rank(right)
    return 1
  if ffw_best_rank(left) == ffw_best_rank(right) && ffw_best_bits(left) < ffw_best_bits(right)
    return 1
  0

root = "bits/tungsten-metaflip/lib/metaflip/seeds/gf2/"
source = ffbc_load_exact(root + "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", 7, 7, 7, 260)
pocket = ffbc_load_exact("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt", 7, 7, 7, 260)
leader = ffbc_load_exact(root + "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt", 7, 7, 7, 260)
fffrpcb_expect("load exact controls", source != nil && pocket != nil && leader != nil)

# The strongest ordinary allowed ticket is a one-flip density-10 child.  It is
# generated at intake rather than checked in: this arm is a same-code,
# same-budget control for the four-flip barrier child.
source_u = i64[260]
source_v = i64[260]
source_w = i64[260]
fffrpcb_expect("scalarize source", fffrp_scalar_scheme(source, source_u, source_v, source_w) == 247)
ordinary_u = i64[8]
ordinary_v = i64[8]
ordinary_w = i64[8]
ordinary_origins = i64[8]
ordinary_stats = i64[32]
ordinary_gain = fffrp_autonomous_ticket(source_u, source_v, source_w, 247, 1, 5, 5, 256, 4, ordinary_u, ordinary_v, ordinary_w, ordinary_origins, ordinary_stats) ## i64
ordinary = fffrp_materialize_selected(source, ordinary_origins, ordinary_u, ordinary_v, ordinary_w, ordinary_stats[7])
fffrpcb_expect("ordinary control", ordinary_gain == 10 && ordinary != nil)

source_probe = fffrpcb_state(source, 72001)
pocket_probe = fffrpcb_state(pocket, 72003)
ordinary_probe = fffrpcb_state(ordinary, 72005)
leader_probe = fffrpcb_state(leader, 72007)
fffrpcb_expect("flat probes", source_probe != nil && pocket_probe != nil && ordinary_probe != nil && leader_probe != nil)

source_id = ffbi_best_id(source_probe) ## i64
pocket_id = ffbi_best_id(pocket_probe) ## i64
ordinary_id = ffbi_best_id(ordinary_probe) ## i64
source_signature = ffbp_structural_signature(source_probe) ## i64
pocket_signature = ffbp_structural_signature(pocket_probe) ## i64
ordinary_signature = ffbp_structural_signature(ordinary_probe) ## i64
source_distance = ffbp_distance(source_probe, pocket_probe) ## i64
leader_distance = ffbp_distance(leader_probe, pocket_probe) ## i64
fffrpcb_expect("support distances", source_distance == 6 && leader_distance == 494)
fffrpcb_expect("canonical pocket basin changes", source_id != pocket_id)

trials = 24 ## i64
steps = 1000000 ## i64
source_wins = 0 ## i64
pocket_wins = 0 ## i64
ordinary_wins = 0 ## i64
pocket_beats_source = 0 ## i64
pocket_beats_ordinary = 0 ## i64
pocket_distinct_source = 0 ## i64
pocket_distinct_ordinary = 0 ## i64
source_bits_sum = 0 ## i64
pocket_bits_sum = 0 ## i64
ordinary_bits_sum = 0 ## i64
source_min = 999999999 ## i64
pocket_min = 999999999 ## i64
ordinary_min = 999999999 ## i64
started = ccall("__w_clock_ms") ## i64
trial = 0 ## i64
while trial < trials
  seed = 73001 + trial * 104729 ## i64
  source_state = fffrpcb_state(source, seed)
  pocket_state = fffrpcb_state(pocket, seed)
  ordinary_state = fffrpcb_state(ordinary, seed)
  fffrpcb_expect("trial states", source_state != nil && pocket_state != nil && ordinary_state != nil)
  ffw_walk(source_state, steps)
  ffw_walk(pocket_state, steps)
  ffw_walk(ordinary_state, steps)
  fffrpcb_expect("trial exact", ffw_verify_best_exact(source_state, 7) == 1 && ffw_verify_best_exact(pocket_state, 7) == 1 && ffw_verify_best_exact(ordinary_state, 7) == 1)

  source_bits = ffw_best_bits(source_state) ## i64
  pocket_bits = ffw_best_bits(pocket_state) ## i64
  ordinary_bits = ffw_best_bits(ordinary_state) ## i64
  source_bits_sum += source_bits
  pocket_bits_sum += pocket_bits
  ordinary_bits_sum += ordinary_bits
  if source_bits < source_min
    source_min = source_bits
  if pocket_bits < pocket_min
    pocket_min = pocket_bits
  if ordinary_bits < ordinary_min
    ordinary_min = ordinary_bits
  if fffrpcb_better(pocket_state, source_state) == 1
    pocket_beats_source += 1
  if fffrpcb_better(pocket_state, ordinary_state) == 1
    pocket_beats_ordinary += 1
  if ffbi_best_id(pocket_state) != ffbi_best_id(source_state)
    pocket_distinct_source += 1
  if ffbi_best_id(pocket_state) != ffbi_best_id(ordinary_state)
    pocket_distinct_ordinary += 1

  best_arm = 0 ## i64
  if fffrpcb_better(pocket_state, source_state) == 1
    best_arm = 1
  selected = source_state
  if best_arm == 1
    selected = pocket_state
  if fffrpcb_better(ordinary_state, selected) == 1
    best_arm = 2
  if best_arm == 0
    source_wins += 1
  if best_arm == 1
    pocket_wins += 1
  if best_arm == 2
    ordinary_wins += 1
  trial += 1
elapsed = ccall("__w_clock_ms") - started ## i64

<< "FIXED_RANK_POCKET_STRUCTURE source-distance=" + source_distance.to_s() + " leader-distance=" + leader_distance.to_s() + " ids=" + source_id.to_s() + "/" + pocket_id.to_s() + "/" + ordinary_id.to_s() + " signatures=" + source_signature.to_s() + "/" + pocket_signature.to_s() + "/" + ordinary_signature.to_s()
<< "FIXED_RANK_POCKET_CONTINUATION trials=" + trials.to_s() + " steps=" + steps.to_s() + " elapsed-ms=" + elapsed.to_s() + " wins-source/pocket/ordinary=" + source_wins.to_s() + "/" + pocket_wins.to_s() + "/" + ordinary_wins.to_s() + " pocket-beats-source=" + pocket_beats_source.to_s() + " pocket-beats-ordinary=" + pocket_beats_ordinary.to_s() + " distinct-source/ordinary=" + pocket_distinct_source.to_s() + "/" + pocket_distinct_ordinary.to_s() + " min-bits=" + source_min.to_s() + "/" + pocket_min.to_s() + "/" + ordinary_min.to_s() + " avg-bits=" + (source_bits_sum / trials).to_s() + "/" + (pocket_bits_sum / trials).to_s() + "/" + (ordinary_bits_sum / trials).to_s()
