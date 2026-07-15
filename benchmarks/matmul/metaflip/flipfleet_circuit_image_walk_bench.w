# Equal-move continuation control for a template-fitted primitive-circuit +1
# shoulder versus an ordinary one-term split +1 shoulder.

use flipfleet_circuit_image_search
use flipfleet_projection_replacement
use flipfleet_global_isotropy

-> ffciwb_expect(label, condition) (String bool) i64
  if !condition
    << "CIRCUIT_IMAGE_WALK_FAIL " + label
    exit(1)
  1

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt", n, capacity, 96101, 4, 4, 500000, 100000) ## i64
ffciwb_expect("base", base_rank == 93 && ffw_verify_best_exact(base, n) == 1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
ffciwb_expect("base export", ffw_export_best(base, base_u, base_v, base_w) == base_rank)

# Materialize the deterministic best two-anchor primitive image once.
circuit_u = i64[12]
circuit_v = i64[12]
circuit_w = i64[12]
circuit_meta = i64[13]
circuit_count = ffcis_search_pairs(base_u, base_v, base_w, base_rank, 4, circuit_u, circuit_v, circuit_w, circuit_meta) ## i64
ffciwb_expect("circuit", circuit_count >= 5 && circuit_count <= 9 && circuit_meta[8] == 1 && ffc_is_primitive_circuit(circuit_u, circuit_v, circuit_w, circuit_count) == 1)
circuit_seed_u = i64[capacity]
circuit_seed_v = i64[capacity]
circuit_seed_w = i64[capacity]
circuit_seed_rank = 0 ## i64
t = 0 ## i64
while t < base_rank
  circuit_seed_rank = ffsdr_toggle_term(circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, base_u[t], base_v[t], base_w[t])
  t += 1
t = 0
while t < circuit_count
  circuit_seed_rank = ffsdr_toggle_term(circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, circuit_u[t], circuit_v[t], circuit_w[t])
  t += 1
ffciwb_expect("circuit shoulder", circuit_seed_rank == 94 && ffpbr_verify_exact(circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, n, n) == 1)

trials = 8 ## i64
moves = 5000000 ## i64
circuit_returns = 0 ## i64
split_returns = 0 ## i64
circuit_rank_wins = 0 ## i64
split_rank_wins = 0 ## i64
circuit_novel_returns = 0 ## i64
split_novel_returns = 0 ## i64
circuit_density_wins = 0 ## i64
split_density_wins = 0 ## i64
circuit_distance_sum = 0 ## i64
split_distance_sum = 0 ## i64
circuit_distance_max = 0 ## i64
split_distance_max = 0 ## i64

trial = 0 ## i64
while trial < trials
  # Build a fresh ordinary split shoulder from the same base terms.
  split_builder = i64[state_size]
  split_loaded = ffw_init_terms_cap(split_builder, base_u, base_v, base_w, base_rank, n, capacity, 96201 + trial * 101, 4, 4, 500000, 100000) ## i64
  ffciwb_expect("split init", split_loaded == base_rank)
  tries = 0 ## i64
  while split_builder[6] == base_rank && tries < 1024
    z = ffw_try_split(split_builder) ## i64
    tries += 1
  ffciwb_expect("split made", split_builder[6] == 94 && ffw_verify_current_exact(split_builder, n) == 1)
  split_u = i64[capacity]
  split_v = i64[capacity]
  split_w = i64[capacity]
  split_rank = ffw_export_current(split_builder, split_u, split_v, split_w) ## i64
  ffciwb_expect("split export", split_rank == 94)

  circuit_state = i64[state_size]
  split_state = i64[state_size]
  circuit_loaded = ffw_init_terms_cap(circuit_state, circuit_seed_u, circuit_seed_v, circuit_seed_w, circuit_seed_rank, n, capacity, 96301 + trial * 103, 4, 4, 500000, 100000) ## i64
  control_loaded = ffw_init_terms_cap(split_state, split_u, split_v, split_w, split_rank, n, capacity, 96401 + trial * 107, 4, 4, 500000, 100000) ## i64
  ffciwb_expect("walk init", circuit_loaded == 94 && control_loaded == 94)
  z = ffw_walk(circuit_state, moves)
  z = ffw_walk(split_state, moves)
  ffciwb_expect("walk exact", ffw_verify_best_exact(circuit_state, n) == 1 && ffw_verify_best_exact(split_state, n) == 1)

  circuit_rank = ffw_best_rank(circuit_state) ## i64
  split_best_rank = ffw_best_rank(split_state) ## i64
  circuit_bits = ffw_best_bits(circuit_state) ## i64
  split_bits = ffw_best_bits(split_state) ## i64
  if circuit_rank <= base_rank
    circuit_returns += 1
  if split_best_rank <= base_rank
    split_returns += 1
  if circuit_rank < base_rank
    circuit_rank_wins += 1
  if split_best_rank < base_rank
    split_rank_wins += 1
  if circuit_rank == base_rank && circuit_bits < 968
    circuit_density_wins += 1
  if split_best_rank == base_rank && split_bits < 968
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
    circuit_novel_returns += 1
  if split_best_rank == base_rank && split_distance > 0
    split_novel_returns += 1
  circuit_distance_sum += circuit_distance
  split_distance_sum += split_distance
  if circuit_distance > circuit_distance_max
    circuit_distance_max = circuit_distance
  if split_distance > split_distance_max
    split_distance_max = split_distance
  << "CIRCUIT_IMAGE_WALK trial=" + trial.to_s() + " circuit=r" + circuit_rank.to_s() + "/d" + circuit_bits.to_s() + "/x" + circuit_distance.to_s() + " split=r" + split_best_rank.to_s() + "/d" + split_bits.to_s() + "/x" + split_distance.to_s()
  trial += 1

<< "CIRCUIT_IMAGE_WALK_SUMMARY trials=" + trials.to_s() + " moves/arm=" + moves.to_s() + " returns=" + circuit_returns.to_s() + "/" + split_returns.to_s() + " rank-wins=" + circuit_rank_wins.to_s() + "/" + split_rank_wins.to_s() + " novel-returns=" + circuit_novel_returns.to_s() + "/" + split_novel_returns.to_s() + " density-wins=" + circuit_density_wins.to_s() + "/" + split_density_wins.to_s() + " distance-avg=" + (circuit_distance_sum / trials).to_s() + "/" + (split_distance_sum / trials).to_s() + " distance-max=" + circuit_distance_max.to_s() + "/" + split_distance_max.to_s()
