# Equal-move continuation control for the best three-anchor +2 circuit image
# against two ordinary random splits from the same 5x5 leader.

use flipfleet_circuit_image_search3
use flipfleet_global_isotropy

-> ffcis3wb_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_SEARCH3_WALK_FAIL " + label
    exit(1)
  1

args = argv()
trials = 8 ## i64
moves = 5000000 ## i64
if args.size() > 0
  trials = args[0].to_i()
if args.size() > 1
  moves = args[1].to_i()
ffcis3wb_expect("arguments", trials >= 1 && trials <= 64 && moves >= 1)

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", n, capacity, 90101, 4, 4, 500000, 100000) ## i64
ffcis3wb_expect("base", base_rank == 93 && ffw_verify_current_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffcis3wb_expect("base export", ffw_export_current(base, base_u, base_v, base_w) == base_rank)

circuit_u = i64[12]
circuit_v = i64[12]
circuit_w = i64[12]
circuit_meta = i64[21]
circuit_count = ffcis3_search_triples(base_u, base_v, base_w, base_rank, 0, 2, 0, circuit_u, circuit_v, circuit_w, circuit_meta) ## i64
ffcis3wb_expect("circuit", circuit_count == 10 && circuit_meta[9] == 2 && circuit_meta[12] == 4 && ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 1)
circuit_seed_u = i64[capacity]
circuit_seed_v = i64[capacity]
circuit_seed_w = i64[capacity]
circuit_seed_rank = ffcis3_apply_circuit(base_u, base_v, base_w, base_rank, circuit_u, circuit_v, circuit_w, circuit_count, circuit_seed_u, circuit_seed_v, circuit_seed_w) ## i64
ffcis3wb_expect("circuit shoulder", circuit_seed_rank == 95)
circuit_gate = i64[state_size]
circuit_loaded = ffw_init_terms_cap(circuit_gate, circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, capacity, 90103, 4, 4, 500000, 100000) ## i64
ffcis3wb_expect("circuit full gate", circuit_loaded == 95 && ffw_verify_current_exact(circuit_gate, n) == 1)

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

trial = 0 ## i64
while trial < trials
  split_builder = i64[state_size]
  # Keep the worker's seeded initial band at four so both +1 splits can be
  # materialized before the matched continuations start.
  split_loaded = ffw_init_terms_cap(split_builder, base_u, base_v, base_w, base_rank, n, capacity, 90203 + trial * 132, 4, 4, 500000, 100000) ## i64
  ffcis3wb_expect("split init", split_loaded == 93)
  tries = 0 ## i64
  while split_builder[6] < 95 && tries < 4096
    z = ffw_try_split(split_builder) ## i64
    tries += 1
  ffcis3wb_expect("two splits", split_builder[6] == 95 && ffw_verify_current_exact(split_builder, n) == 1)
  split_u = i64[capacity]
  split_v = i64[capacity]
  split_w = i64[capacity]
  split_rank = ffw_export_current(split_builder, split_u, split_v, split_w) ## i64
  ffcis3wb_expect("split export", split_rank == 95)

  circuit_state = i64[state_size]
  split_state = i64[state_size]
  circuit_init = ffw_init_terms_cap(circuit_state, circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, capacity, 90301 + trial * 137, 4, 4, 500000, 100000) ## i64
  split_init = ffw_init_terms_cap(split_state, split_u, split_v, split_w, split_rank, n, capacity, 90401 + trial * 139, 4, 4, 500000, 100000) ## i64
  ffcis3wb_expect("walk init", circuit_init == 95 && split_init == 95)
  z = ffw_walk(circuit_state, moves)
  z = ffw_walk(split_state, moves)
  ffcis3wb_expect("walk exact", ffw_verify_best_exact(circuit_state, n) == 1 && ffw_verify_best_exact(split_state, n) == 1)

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
  if circuit_rank == base_rank && circuit_density < 968
    circuit_density_wins += 1
  if split_best_rank == base_rank && split_density < 968
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
  << "CIRCUIT_IMAGE_SEARCH3_WALK trial=" + trial.to_s() + " circuit=r" + circuit_rank.to_s() + "/d" + circuit_density.to_s() + "/x" + circuit_distance.to_s() + " split=r" + split_best_rank.to_s() + "/d" + split_density.to_s() + "/x" + split_distance.to_s()
  trial += 1

<< "CIRCUIT_IMAGE_SEARCH3_WALK_SUMMARY trials=" + trials.to_s() + " moves/arm=" + moves.to_s() + " returns=" + circuit_returns.to_s() + "/" + split_returns.to_s() + " rank-wins=" + circuit_rank_wins.to_s() + "/" + split_rank_wins.to_s() + " density-wins=" + circuit_density_wins.to_s() + "/" + split_density_wins.to_s() + " novel-returns=" + circuit_novel.to_s() + "/" + split_novel.to_s() + " distance-avg=" + (circuit_distance_sum / trials).to_s() + "/" + (split_distance_sum / trials).to_s()
