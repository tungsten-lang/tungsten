# Deterministic equal-move comparison of the old split+split seed against the
# mixed recipe beam feeding the same CPU continuation.  This is a scheduling
# probe, not a correctness test or record claim.

use flipfleet_beam_recipes

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, capacity, 88001, 4, 4, 500000, 100000) ## i64
if base_rank != 93 || ffw_verify_best_exact(base, n) != 1
  << "flipfleet_beam_recipes_bench: seed failure"
  exit(1)
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_best(base, base_u, base_v, base_w) ## i64

trials = 5 ## i64
moves = 5000000 ## i64
old_returns = 0 ## i64
beam_returns = 0 ## i64
old_density_wins = 0 ## i64
beam_density_wins = 0 ## i64
trial = 0 ## i64
while trial < trials
  old_u = i64[capacity]
  old_v = i64[capacity]
  old_w = i64[capacity]
  z = ffbr_copy(base_u, base_v, base_w, base_rank, old_u, old_v, old_w) ## i64
  old_meta = i64[8]
  old_seed_rank = ffe_compose(old_u, old_v, old_w, base_rank, capacity, 91001 + trial * 101, old_meta) ## i64
  old_state = i64[state_size]
  z = ffw_init_terms_cap(old_state, old_u, old_v, old_w, old_seed_rank, n, capacity, 92001 + trial * 103, 4, 4, 500000, 100000) ## i64

  beam_u = i64[capacity]
  beam_v = i64[capacity]
  beam_w = i64[capacity]
  beam_recipe = i64[3]
  beam_meta = i64[8]
  beam_seed_rank = ffbr_beam_search(base_u, base_v, base_w, base_rank, capacity, n, 3, 8, 93001 + trial * 107, beam_u, beam_v, beam_w, beam_recipe, beam_meta) ## i64
  beam_state = i64[state_size]
  z = ffw_init_terms_cap(beam_state, beam_u, beam_v, beam_w, beam_seed_rank, n, capacity, 94001 + trial * 109, 4, 4, 500000, 100000) ## i64

  z = ffw_walk(old_state, moves)
  z = ffw_walk(beam_state, moves)
  if ffw_verify_best_exact(old_state, n) != 1 || ffw_verify_best_exact(beam_state, n) != 1
    << "flipfleet_beam_recipes_bench: exactness failure"
    exit(1)
  old_rank = ffw_best_rank(old_state) ## i64
  beam_rank = ffw_best_rank(beam_state) ## i64
  old_bits = ffw_best_bits(old_state) ## i64
  beam_bits = ffw_best_bits(beam_state) ## i64
  if old_rank <= base_rank
    old_returns += 1
  if beam_rank <= base_rank
    beam_returns += 1
  if old_rank == base_rank && old_bits < ffw_best_bits(base)
    old_density_wins += 1
  if beam_rank == base_rank && beam_bits < ffw_best_bits(base)
    beam_density_wins += 1
  << "trial=" + trial.to_s() + " old_seed=r" + old_seed_rank.to_s() + " old=r" + old_rank.to_s() + "/d" + old_bits.to_s() + " beam_seed=r" + beam_seed_rank.to_s() + " beam=r" + beam_rank.to_s() + "/d" + beam_bits.to_s() + " recipe=" + beam_recipe[0].to_s() + "," + beam_recipe[1].to_s() + "," + beam_recipe[2].to_s()
  trial += 1

<< "summary trials=" + trials.to_s() + " moves/arm=" + moves.to_s() + " old_returns=" + old_returns.to_s() + " beam_returns=" + beam_returns.to_s() + " old_density_wins=" + old_density_wins.to_s() + " beam_density_wins=" + beam_density_wins.to_s()
