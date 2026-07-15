# Equal-move continuation control for a gauge-resistant three-anchor circuit
# shoulder versus four ordinary random splits from the same source.
#
# Usage: seed n source_density trials moves [fit_cap] [trial_offset] [publish]

use flipfleet_circuit_image_search3
use flipfleet_global_isotropy

-> ffcis3gwb_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_SEARCH3_GAUGE_WALK_FAIL " + label
    exit(1)
  1

args = argv()
if args.size() < 5
  << "usage: flipfleet_circuit_image_search3_gauge_walk_bench seed n source_density trials moves [fit_cap]"
  exit(2)
path = args[0]
n = args[1].to_i() ## i64
source_density = args[2].to_i() ## i64
trials = args[3].to_i() ## i64
moves = args[4].to_i() ## i64
fit_cap = 0 ## i64
if args.size() > 5
  fit_cap = args[5].to_i()
trial_offset = 0 ## i64
if args.size() > 6
  trial_offset = args[6].to_i()
ffcis3gwb_expect("arguments", n >= 3 && n <= 7 && source_density > 0 && trials >= 1 && trials <= 64 && moves >= 1 && fit_cap >= 0 && trial_offset >= 0)

capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, path, n, capacity, 91103, 6, 4, 500000, 100000) ## i64
ffcis3gwb_expect("base", base_rank > 0 && ffw_current_bits(base) == source_density && ffw_verify_current_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffcis3gwb_expect("base export", ffw_export_current(base, base_u, base_v, base_w) == base_rank)

circuit_u = i64[12]
circuit_v = i64[12]
circuit_w = i64[12]
circuit_meta = i64[21]
circuit_count = ffcis3_search_triples(base_u, base_v, base_w, base_rank, fit_cap, 0, 1, circuit_u, circuit_v, circuit_w, circuit_meta) ## i64
ffcis3gwb_expect("gauge-resistant circuit", circuit_count >= 10 && circuit_count <= 12 && circuit_meta[9] == 4 && circuit_meta[20] > circuit_meta[12] && ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 1)
circuit_seed_u = i64[capacity]
circuit_seed_v = i64[capacity]
circuit_seed_w = i64[capacity]
circuit_seed_rank = ffcis3_apply_circuit(base_u, base_v, base_w, base_rank, circuit_u, circuit_v, circuit_w, circuit_count, circuit_seed_u, circuit_seed_v, circuit_seed_w) ## i64
ffcis3gwb_expect("circuit shoulder rank", circuit_seed_rank == base_rank + 4)
circuit_gate = i64[state_size]
circuit_loaded = ffw_init_terms_cap(circuit_gate, circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, capacity, 91107, 6, 4, 500000, 100000) ## i64
ffcis3gwb_expect("circuit shoulder exact", circuit_loaded == circuit_seed_rank && ffw_verify_current_exact(circuit_gate, n) == 1)

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
circuit_max_distance = 0 ## i64
split_max_distance = 0 ## i64
published = 0 ## i64
published_density = 9223372036854775807 ## i64

trial = 0 ## i64
while trial < trials
  trial_id = trial + trial_offset ## i64
  # Seeds are 3 modulo 4, keeping the worker's initial rank band at four.
  split_builder = i64[state_size]
  split_loaded = ffw_init_terms_cap(split_builder, base_u, base_v, base_w, base_rank, n, capacity, 91203 + trial_id * 132, 6, 4, 500000, 100000) ## i64
  ffcis3gwb_expect("split init", split_loaded == base_rank)
  tries = 0 ## i64
  while split_builder[6] < base_rank + 4 && tries < 16384
    z = ffw_try_split(split_builder) ## i64
    tries += 1
  ffcis3gwb_expect("four splits", split_builder[6] == base_rank + 4 && ffw_verify_current_exact(split_builder, n) == 1)
  split_u = i64[capacity]
  split_v = i64[capacity]
  split_w = i64[capacity]
  split_rank = ffw_export_current(split_builder, split_u, split_v, split_w) ## i64
  ffcis3gwb_expect("split export", split_rank == base_rank + 4)

  circuit_state = i64[state_size]
  split_state = i64[state_size]
  circuit_init = ffw_init_terms_cap(circuit_state, circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, capacity, 91301 + trial_id * 137, 6, 4, 500000, 100000) ## i64
  split_init = ffw_init_terms_cap(split_state, split_u, split_v, split_w, split_rank, n, capacity, 91401 + trial_id * 139, 6, 4, 500000, 100000) ## i64
  ffcis3gwb_expect("walk init", circuit_init == base_rank + 4 && split_init == base_rank + 4)
  z = ffw_walk(circuit_state, moves)
  z = ffw_walk(split_state, moves)
  ffcis3gwb_expect("walk exact", ffw_verify_best_exact(circuit_state, n) == 1 && ffw_verify_best_exact(split_state, n) == 1)

  circuit_rank = ffw_best_rank(circuit_state) ## i64
  split_best_rank = ffw_best_rank(split_state) ## i64
  circuit_density = ffw_best_bits(circuit_state) ## i64
  split_density = ffw_best_bits(split_state) ## i64
  if circuit_rank <= base_rank
    circuit_returns += 1
  if split_best_rank <= base_rank
    split_returns += 1
  if circuit_rank < base_rank
    circuit_rank_wins += 1
  if split_best_rank < base_rank
    split_rank_wins += 1
  if circuit_rank == base_rank && circuit_density < source_density
    circuit_density_wins += 1
  if split_best_rank == base_rank && split_density < source_density
    split_density_wins += 1

  circuit_best_u = i64[capacity]
  circuit_best_v = i64[capacity]
  circuit_best_w = i64[capacity]
  split_best_u = i64[capacity]
  split_best_v = i64[capacity]
  split_best_w = i64[capacity]
  z = ffw_export_best(circuit_state, circuit_best_u, circuit_best_v, circuit_best_w)
  z = ffw_export_best(split_state, split_best_u, split_best_v, split_best_w)
  circuit_distance = ffgir_term_set_distance(base_u, base_v, base_w, base_rank, circuit_best_u, circuit_best_v, circuit_best_w, circuit_rank) ## i64
  split_distance = ffgir_term_set_distance(base_u, base_v, base_w, base_rank, split_best_u, split_best_v, split_best_w, split_best_rank) ## i64
  if circuit_rank == base_rank && circuit_distance > 0
    circuit_novel += 1
  if split_best_rank == base_rank && split_distance > 0
    split_novel += 1
  circuit_distance_sum += circuit_distance
  split_distance_sum += split_distance
  if circuit_distance > circuit_max_distance
    circuit_max_distance = circuit_distance
  if split_distance > split_max_distance
    split_max_distance = split_distance
  if args.size() > 7
    if circuit_rank == base_rank && circuit_density < source_density && circuit_density < published_density
      published = ffw_dump_best(circuit_state, args[7])
      published_density = circuit_density
    if split_best_rank == base_rank && split_density < source_density && split_density < published_density
      published = ffw_dump_best(split_state, args[7])
      published_density = split_density
  << "CIRCUIT_IMAGE_SEARCH3_GAUGE_WALK trial=" + trial_id.to_s() + " circuit=r" + circuit_rank.to_s() + "/d" + circuit_density.to_s() + "/x" + circuit_distance.to_s() + " split=r" + split_best_rank.to_s() + "/d" + split_density.to_s() + "/x" + split_distance.to_s()
  trial += 1

<< "CIRCUIT_IMAGE_SEARCH3_GAUGE_WALK_SUMMARY n=" + n.to_s() + " source=r" + base_rank.to_s() + "/d" + source_density.to_s() + " circuit=" + circuit_count.to_s() + "/overlap" + circuit_meta[12].to_s() + "/min-added" + circuit_meta[20].to_s() + " trials=" + trials.to_s() + " moves/arm=" + moves.to_s() + " returns=" + circuit_returns.to_s() + "/" + split_returns.to_s() + " rank-wins=" + circuit_rank_wins.to_s() + "/" + split_rank_wins.to_s() + " density-wins=" + circuit_density_wins.to_s() + "/" + split_density_wins.to_s() + " novel-returns=" + circuit_novel.to_s() + "/" + split_novel.to_s() + " distance-avg=" + (circuit_distance_sum / trials).to_s() + "/" + (split_distance_sum / trials).to_s() + " distance-max=" + circuit_max_distance.to_s() + "/" + split_max_distance.to_s() + " published=" + published.to_s() + "/d" + published_density.to_s()
