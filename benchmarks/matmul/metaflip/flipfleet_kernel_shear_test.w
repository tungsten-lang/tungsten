use flipfleet_kernel_shear

-> ffks_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffks_test_set3(values, a, b, c) (i64[] i64 i64 i64) i64
  values[0] = a
  values[1] = b
  values[2] = c
  3

# Recover the checked-in 5x5 distance-six one-axis kernel relation.  The
# solver sees only the three old terms and axis assignment U,U,W; no target is
# supplied.
old_u = i64[3]
old_v = i64[3]
old_w = i64[3]
z = ffks_test_set3(old_u, 524288, 11337728, 16777216) ## i64
z = ffks_test_set3(old_v, 5406720, 168965, 5248005)
z = ffks_test_set3(old_w, 32768, 32768, 1048577)
axes = i64[3]
axes[0] = 0
axes[1] = 0
axes[2] = 2
out_u = i64[3]
out_v = i64[3]
out_w = i64[3]
meta = i64[8]
found = ffks_find_novel(old_u, old_v, old_w, 3, axes, 25, out_u, out_v, out_w, meta) ## i64
z = ffks_test_expect("kernel solver finds relation", found == 3)
z = ffks_test_expect("kernel relation exact", fftc_local_exact(old_u, old_v, old_w, 3, out_u, out_v, out_w, 3) == 1)
z = ffks_test_expect("kernel relation changes several terms", meta[3] >= 2)
z = ffks_test_expect("kernel relation is not one flip", ffks_is_one_flip(old_u, old_v, old_w, 3, out_u, out_v, out_w) == 0)
z = ffks_test_expect("elimination reports dependency", meta[0] == 75 && meta[2] > 0)

# Applying the deltas again is the inverse because every changed factor is
# XORed by the same kernel vector.
delta_u = i64[3]
delta_v = i64[3]
delta_w = i64[3]
i = 0 ## i64
while i < 3
  delta_u[i] = old_u[i] ^ out_u[i]
  delta_v[i] = old_v[i] ^ out_v[i]
  delta_w[i] = old_w[i] ^ out_w[i]
  i += 1
round_u = i64[3]
round_v = i64[3]
round_w = i64[3]
i = 0
while i < 3
  round_u[i] = out_u[i] ^ delta_u[i]
  round_v[i] = out_v[i] ^ delta_v[i]
  round_w[i] = out_w[i] ^ delta_w[i]
  i += 1
z = ffks_test_expect("kernel shear involution", fftc_terms_same_set(old_u, old_v, old_w, 3, round_u, round_v, round_w, 3) == 1)

# A pair-flip-only kernel is quotiented out rather than advertised as novel.
pair_u = i64[2]
pair_v = i64[2]
pair_w = i64[2]
pair_u[0] = 1
pair_u[1] = 2
pair_v[0] = 4
pair_v[1] = 8
pair_w[0] = 16
pair_w[1] = 16
pair_axes = i64[2]
pair_axes[0] = 0
pair_axes[1] = 1
pair_out_u = i64[2]
pair_out_v = i64[2]
pair_out_w = i64[2]
pair_meta = i64[8]
pair_found = ffks_find_novel(pair_u, pair_v, pair_w, 2, pair_axes, 5, pair_out_u, pair_out_v, pair_out_w, pair_meta) ## i64
z = ffks_test_expect("ordinary tangent quotient", pair_found == 0 || ffks_is_one_flip(pair_u, pair_v, pair_w, 2, pair_out_u, pair_out_v, pair_out_w) == 0)

# Positional distance is not a safe shortcut: reorder a legitimate pair-flip
# endpoint so all three slots differ.  Its multiset distance is still two and
# the exhaustive classifier must recognize it as one ordinary flip.
permuted_u = i64[3]
permuted_v = i64[3]
permuted_w = i64[3]
permuted_u[0] = 1
permuted_v[0] = 2
permuted_w[0] = 4
permuted_u[1] = 1
permuted_v[1] = 8
permuted_w[1] = 16
permuted_u[2] = 32
permuted_v[2] = 64
permuted_w[2] = 128
flipped_u = i64[3]
flipped_v = i64[3]
flipped_w = i64[3]
z = fftc_copy_terms(permuted_u, permuted_v, permuted_w, 3, flipped_u, flipped_v, flipped_w)
z = ffks_test_expect("construct one-flip permutation fixture", fftc_apply_code(flipped_u, flipped_v, flipped_w, 3, 0, 0 - 1) == 1)
saved_u = flipped_u[0] ## i64
saved_v = flipped_v[0] ## i64
saved_w = flipped_w[0] ## i64
flipped_u[0] = flipped_u[1]
flipped_v[0] = flipped_v[1]
flipped_w[0] = flipped_w[1]
flipped_u[1] = flipped_u[2]
flipped_v[1] = flipped_v[2]
flipped_w[1] = flipped_w[2]
flipped_u[2] = saved_u
flipped_v[2] = saved_v
flipped_w[2] = saved_w
z = ffks_test_expect("permuted one-flip multiset distance", ffks_term_set_delta(permuted_u, permuted_v, permuted_w, 3, flipped_u, flipped_v, flipped_w) == 2)
z = ffks_test_expect("permuted one-flip exact quotient", ffks_is_one_flip(permuted_u, permuted_v, permuted_w, 3, flipped_u, flipped_v, flipped_w) == 1)

# Full independent 5x5 splice gate.
n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
loaded = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, capacity, 112233, 4, 2, 1000, 250) ## i64
z = ffks_test_expect("5x5 frontier loads", loaded == 93 && ffw_verify_current_exact(state, n) == 1)
all_u = i64[capacity]
all_v = i64[capacity]
all_w = i64[capacity]
rank = ffw_export_current(state, all_u, all_v, all_w) ## i64
i = 0
while i < 3
  index = ffsr_find_candidate_term(all_u, all_v, all_w, rank, old_u[i], old_v[i], old_w[i]) ## i64
  z = ffks_test_expect("kernel source live " + i.to_s(), index >= 0)
  all_u[index] = out_u[i]
  all_v[index] = out_v[i]
  all_w[index] = out_w[i]
  i += 1
endpoint = i64[ffw_state_size(capacity)]
endpoint_rank = ffw_init_terms_cap(endpoint, all_u, all_v, all_w, rank, n, capacity, 332211, 4, 2, 1000, 250) ## i64
z = ffks_test_expect("kernel shear full splice exact", endpoint_rank == 93 && ffw_verify_current_exact(endpoint, n) == 1)

# Whole-frontier striped plan: this is the genuinely global operator rather
# than a planted three-term call.  Phase two discovers an exact distance-six
# dependency directly inside all 93 live terms, and the rebuilt endpoint must
# pass the independent complete 5x5 tensor gate.
z = ffks_test_expect("restore original frontier export", ffw_export_current(state, all_u, all_v, all_w) == rank)
global_axes = i64[capacity]
z = ffks_test_expect("global striped axis plan", ffks_fill_axis_plan(all_u, all_v, all_w, rank, 5, 104729, global_axes) == rank)
global_u = i64[capacity]
global_v = i64[capacity]
global_w = i64[capacity]
global_meta = i64[8]
global_work = ffks_work_words(rank, n * n) ## i64
z = ffks_test_expect("global work estimate bounded", global_work > 0 && global_work < 1000000)
global_found = ffks_find_novel_bounded(all_u, all_v, all_w, rank, global_axes, n * n, 1000000, global_u, global_v, global_w, global_meta) ## i64
z = ffks_test_expect("global kernel finds nontrivial dependency", global_found == rank && global_meta[3] >= 3 && global_meta[4] == 1 && global_meta[7] == 1)
global_endpoint = i64[ffw_state_size(capacity)]
global_rank = ffw_init_terms_cap(global_endpoint, global_u, global_v, global_w, rank, n, capacity, 443322, 4, 2, 1000, 250) ## i64
z = ffks_test_expect("global full-tensor splice exact", global_rank == 93 && ffw_verify_current_exact(global_endpoint, n) == 1)

cap_meta = i64[8]
cap_u = i64[capacity]
cap_v = i64[capacity]
cap_w = i64[capacity]
cap_found = ffks_find_novel_bounded(all_u, all_v, all_w, rank, global_axes, n * n, global_work - 1, cap_u, cap_v, cap_w, cap_meta) ## i64
z = ffks_test_expect("global allocation cap is enforced", cap_found == 0 && cap_meta[6] == global_work && cap_meta[7] == -2)

bad_axes = i64[3]
bad_axes[0] = 3
z = ffks_test_expect("bad axis rejected", ffks_find_novel(old_u, old_v, old_w, 3, bad_axes, 25, out_u, out_v, out_w, meta) == 0)

<< "flipfleet_kernel_shear_test: all checks passed"
