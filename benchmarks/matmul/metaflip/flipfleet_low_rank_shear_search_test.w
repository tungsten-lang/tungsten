use flipfleet_low_rank_shear_search

-> fflrs_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

# Planted rank-two correction absorption.  The enumerator receives only the
# four live terms and must derive both complementary factors and carriers.
plant_u = i64[4]
plant_v = i64[4]
plant_w = i64[4]
plant_u[0] = 1
plant_v[0] = 2
plant_w[0] = 4
plant_u[1] = 8
plant_v[1] = 16
plant_w[1] = 32
plant_u[2] = 64
plant_v[2] = 2
plant_w[2] = 1
plant_u[3] = 64
plant_v[3] = 16
plant_w[3] = 2
selected = i64[4]
out_u = i64[4]
out_v = i64[4]
out_w = i64[4]
meta = i64[8]
made = fflrs_find_pair_absorb(plant_u, plant_v, plant_w, 4, 0, selected, out_u, out_v, out_w, meta) ## i64
z = fflrs_test_expect("rank-two absorbed shear found", made == 4 && meta[0] == 2)
z = fflrs_test_expect("rank-two absorbed shear exact", fftc_local_exact(plant_u, plant_v, plant_w, 4, out_u, out_v, out_w, 4) == 1)
z = fflrs_test_expect("rank-two endpoint novel to one flip", fflrs_is_one_flip(plant_u, plant_v, plant_w, 4, out_u, out_v, out_w) == 0)

# Run the actual structural enumerator on the complete checked-in 5x5
# frontier, then splice and independently reconstruct all n^6 coefficients.
n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
loaded = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, capacity, 778899, 4, 2, 1000, 250) ## i64
z = fflrs_test_expect("5x5 frontier loads", loaded == 93 && ffw_verify_current_exact(state, n) == 1)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
scheme_rank = ffw_export_current(state, all_u, all_v, all_w) ## i64
real_selected = i64[4]
real_out_u = i64[4]
real_out_v = i64[4]
real_out_w = i64[4]
real_meta = i64[8]
real_made = fflrs_find_pair_absorb(all_u, all_v, all_w, scheme_rank, 0, real_selected, real_out_u, real_out_v, real_out_w, real_meta) ## i64
z = fflrs_test_expect("5x5 absorbed shear enumerated", real_made == 3 || real_made == 4)
if real_made > 0
  local_u = i64[4]
  local_v = i64[4]
  local_w = i64[4]
  i = 0 ## i64
  while i < real_made
    local_u[i] = all_u[real_selected[i]]
    local_v[i] = all_v[real_selected[i]]
    local_w[i] = all_w[real_selected[i]]
    i += 1
  z = fflrs_test_expect("5x5 enumerated local identity exact", fftc_local_exact(local_u, local_v, local_w, real_made, real_out_u, real_out_v, real_out_w, real_made) == 1)
  applied = ffsr_apply_current(state, real_selected, real_made, real_out_u, real_out_v, real_out_w, real_made) ## i64
  z = fflrs_test_expect("5x5 absorbed shear full splice exact", applied == 93 && ffw_verify_current_exact(state, n) == 1)

bad_u = i64[2]
bad_v = i64[2]
bad_w = i64[2]
z = fflrs_test_expect("undersized scheme rejected", fflrs_find_pair_absorb(bad_u, bad_v, bad_w, 2, 0, selected, out_u, out_v, out_w, meta) == 0)

<< "low-rank shear search: real-rank=" + real_made.to_s() + " correction-rank=" + real_meta[0].to_s() + " pairs=" + real_meta[3].to_s() + " carriers=" + real_meta[4].to_s()
<< "flipfleet_low_rank_shear_search_test: all checks passed"
