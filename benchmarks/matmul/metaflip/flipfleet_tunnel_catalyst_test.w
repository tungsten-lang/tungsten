use flipfleet_tunnel_catalyst

-> fftc_test_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

-> fftc_test_set3(values, a, b, c) (i64[] i64 i64 i64) i64
  values[0] = a
  values[1] = b
  values[2] = c
  1

# Ordered pair flips are exact and the reverse ordering exposes the other
# two-term path.
pair_u = i64[2]
pair_v = i64[2]
pair_w = i64[2]
pair_u[0] = 3
pair_u[1] = 3
pair_v[0] = 1
pair_v[1] = 3
pair_w[0] = 3
pair_w[1] = 2
old_pair_u = i64[2]
old_pair_v = i64[2]
old_pair_w = i64[2]
z = fftc_copy_terms(pair_u, pair_v, pair_w, 2, old_pair_u, old_pair_v, old_pair_w) ## i64
z = fftc_test_expect("compatible pair flips", fftc_apply_flip(pair_u, pair_v, pair_w, 2, 1, 0, 0) == 1)
z = fftc_test_expect("pair flip exact", fftc_local_exact(old_pair_u, old_pair_v, old_pair_w, 2, pair_u, pair_v, pair_w, 2) == 1)
z = fftc_test_expect("incompatible pair rejected", fftc_apply_flip(pair_u, pair_v, pair_w, 2, 0, 1, 1) == 0)

# Real rank-93 5x5 distance-six endpoint, recovered by exhaustive W->V->W
# three-flip tunneling rather than supplied to a validator alone.
real_old_u = i64[3]
real_old_v = i64[3]
real_old_w = i64[3]
real_want_u = i64[3]
real_want_v = i64[3]
real_want_w = i64[3]
z = fftc_test_set3(real_old_u, 524288, 11337728, 16777216)
z = fftc_test_set3(real_old_v, 5406720, 168965, 5248005)
z = fftc_test_set3(real_old_w, 32768, 32768, 1048577)
z = fftc_test_set3(real_want_u, 17301504, 28114944, 16777216)
z = fftc_test_set3(real_want_v, 5406720, 168965, 5248005)
z = fftc_test_set3(real_want_w, 32768, 32768, 1081345)
real_out_u = i64[3]
real_out_v = i64[3]
real_out_w = i64[3]
tunnel_path = i64[3]
found_tunnel = fftc_find_tunnel3(real_old_u, real_old_v, real_old_w, real_want_u, real_want_v, real_want_w, real_out_u, real_out_v, real_out_w, tunnel_path) ## i64
z = fftc_test_expect("three-flip tunnel recovered", found_tunnel == 3)
z = fftc_test_expect("three-flip endpoint exact", fftc_local_exact(real_old_u, real_old_v, real_old_w, 3, real_out_u, real_out_v, real_out_w, 3) == 1)

# Labeled R+2 catalyst: the enumerator must find the planted four-flip braid,
# return the two labels to an equal term, cancel them, and expose a different
# exact rank-three endpoint.
cat_old_u = i64[3]
cat_old_v = i64[3]
cat_old_w = i64[3]
cat_want_u = i64[3]
cat_want_v = i64[3]
cat_want_w = i64[3]
z = fftc_test_set3(cat_old_u, 1, 6, 1)
z = fftc_test_set3(cat_old_v, 2, 2, 7)
z = fftc_test_set3(cat_old_w, 2, 5, 2)
z = fftc_test_set3(cat_want_u, 1, 6, 6)
z = fftc_test_set3(cat_want_v, 5, 5, 7)
z = fftc_test_set3(cat_want_w, 2, 5, 5)
cat_out_u = i64[3]
cat_out_v = i64[3]
cat_out_w = i64[3]
cat_path = i64[4]
found_cat = fftc_find_catalyst4(cat_old_u, cat_old_v, cat_old_w, 6, 7, 7, cat_want_u, cat_want_v, cat_want_w, cat_out_u, cat_out_v, cat_out_w, cat_path) ## i64
z = fftc_test_expect("labeled catalyst braid recovered", found_cat == 4)
z = fftc_test_expect("catalyst endpoint changes terms", fftc_terms_same_set(cat_old_u, cat_old_v, cat_old_w, 3, cat_out_u, cat_out_v, cat_out_w, 3) == 0)
z = fftc_test_expect("catalyst endpoint exact", fftc_local_exact(cat_old_u, cat_old_v, cat_old_w, 3, cat_out_u, cat_out_v, cat_out_w, 3) == 1)
z = fftc_test_expect("zero catalyst rejected", fftc_find_catalyst4(cat_old_u, cat_old_v, cat_old_w, 0, 7, 7, cat_want_u, cat_want_v, cat_want_w, cat_out_u, cat_out_v, cat_out_w, cat_path) == 0)

# Splice the discovered tunnel into the checked-in full 5x5 frontier and run
# the independent n^6 reconstruction gate.
n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
loaded = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, capacity, 97531, 4, 2, 1000, 250) ## i64
z = fftc_test_expect("5x5 frontier loads", loaded == 93 && ffw_verify_current_exact(state, n) == 1)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
rank = ffw_export_current(state, all_u, all_v, all_w) ## i64
i = 0 ## i64
while i < 3
  index = ffsr_find_candidate_term(all_u, all_v, all_w, rank, real_old_u[i], real_old_v[i], real_old_w[i]) ## i64
  z = fftc_test_expect("tunnel source live " + i.to_s(), index >= 0)
  all_u[index] = real_out_u[i]
  all_v[index] = real_out_v[i]
  all_w[index] = real_out_w[i]
  i += 1
endpoint = i64[ffw_state_size(capacity)]
endpoint_rank = ffw_init_terms_cap(endpoint, all_u, all_v, all_w, rank, n, capacity, 86420, 4, 2, 1000, 250) ## i64
z = fftc_test_expect("atomic tunnel full splice exact", endpoint_rank == 93 && ffw_verify_current_exact(endpoint, n) == 1)

<< "flipfleet_tunnel_catalyst_test: all checks passed"
