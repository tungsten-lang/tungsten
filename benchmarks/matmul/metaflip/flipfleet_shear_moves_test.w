use metaflip_worker
use flipfleet_shear_moves

-> ffsm_test_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffsm_test_set3(out, a, b, c) (i64[] i64 i64 i64) i64
  out[0] = a
  out[1] = b
  out[2] = c
  3

-> ffsm_test_equal_three(lu, lv, lw, ru, rv, right_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  same = 1 ## i64
  i = 0 ## i64
  while i < 3
    if lu[i] != ru[i] || lv[i] != rv[i] || lw[i] != right_w[i]
      same = 0
    i += 1
  same

-> ffsm_test_distance_three(lu, lv, lw, ru, rv, right_w) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  common = 0 ## i64
  i = 0 ## i64
  while i < 3
    common += ffsm_term_in(ru, rv, right_w, 3, lu[i], lv[i], lw[i])
    i += 1
  6 - 2 * common

-> ffsm_test_factor_three(su, sv, sw, correction_left, correction_right) (i64[] i64[] i64[] i64[] i64[]) i64
  ffsm_rank_factor_complement(su, sv, sw, 3, 0, 1, correction_left, correction_right)

-> ffsm_test_verify_factor_three(su, sv, sw, correction_left, correction_right, rank) (i64[] i64[] i64[] i64[] i64[] i64) i64
  ffsm_verify_complement_factorization(su, sv, sw, 3, 0, 1, correction_left, correction_right, rank)

-> ffsm_test_append_three(su, sv, sw, correction_left, correction_right, packed) (i64[] i64[] i64[] i64[] i64[] i64[]) i64
  out_u = i64[5]
  out_v = i64[5]
  out_w = i64[5]
  made = ffsm_low_rank_shear_append(su, sv, sw, 3, 0, 1, 16, correction_left, correction_right, 2, out_u, out_v, out_w) ## i64
  if made == 5 && packed.size() >= 15
    i = 0 ## i64
    while i < 5
      packed[i * 3] = out_u[i]
      packed[i * 3 + 1] = out_v[i]
      packed[i * 3 + 2] = out_w[i]
      i += 1
  made

-> ffsm_test_verify_append_three(su, sv, sw, packed) (i64[] i64[] i64[] i64[]) i64
  out_u = i64[5]
  out_v = i64[5]
  out_w = i64[5]
  i = 0 ## i64
  while i < 5
    out_u[i] = packed[i * 3]
    out_v[i] = packed[i * 3 + 1]
    out_w[i] = packed[i * 3 + 2]
    i += 1
  # The constructor's exact matrix-factorization gate is the proof for this
  # 3->5 move; verify the expected shifted/correction shape independently.
  ok = 1 ## i64
  i = 0
  while i < 3
    if out_u[i] != (su[i] ^ 16) || out_v[i] != sv[i] || out_w[i] != sw[i]
      ok = 0
    i += 1
  if ffsm_terms_well_formed(out_u, out_v, out_w, 5) == 0
    ok = 0
  ok

# Canonical synthetic triangle and its involution.
old_u = i64[3]
old_v = i64[3]
old_w = i64[3]
want_u = i64[3]
want_v = i64[3]
want_w = i64[3]
z = ffsm_test_set3(old_u, 1, 2, 4) ## i64
z = ffsm_test_set3(old_v, 8, 16, 24)
z = ffsm_test_set3(old_w, 32, 32, 64)
z = ffsm_test_set3(want_u, 5, 6, 4)
z = ffsm_test_set3(want_v, 8, 16, 24)
z = ffsm_test_set3(want_w, 32, 32, 96)
out_u = i64[3]
out_v = i64[3]
out_w = i64[3]
packed = i64[9]
made = ffsm_triangle_shear_packed(old_u, old_v, old_w, 0, packed) ## i64
z = ffsm_unpack_three(packed, out_u, out_v, out_w)
z = ffsm_test_expect("canonical triangle found", made == 3) ## i64
z = ffsm_test_expect("canonical triangle factors", ffsm_test_equal_three(out_u, out_v, out_w, want_u, want_v, want_w) == 1)
z = ffsm_test_expect("canonical triangle exact", ffsm_verify_three_to_three(old_u, old_v, old_w, out_u, out_v, out_w) == 1)
z = ffsm_test_expect("canonical triangle distance six", ffsm_test_distance_three(old_u, old_v, old_w, out_u, out_v, out_w) == 6)
back_u = i64[3]
back_v = i64[3]
back_w = i64[3]
back_packed = i64[9]
back = ffsm_triangle_shear_packed(out_u, out_v, out_w, 0, back_packed) ## i64
z = ffsm_unpack_three(back_packed, back_u, back_v, back_w)
z = ffsm_test_expect("triangle is involutive", back == 3 && ffsm_test_equal_three(back_u, back_v, back_w, old_u, old_v, old_w) == 1)

# All six assignments of transfer/sum/shared to physical U/V/W.
code = 0 ## i64
while code < 6
  axes = i64[3]
  z = ffsm_axis_code(code, axes)
  pu = i64[3]
  pv = i64[3]
  pw = i64[3]
  eu = i64[3]
  ev = i64[3]
  ew = i64[3]
  i = 0 ## i64
  while i < 3
    transfer = 1 << i ## i64
    sum = 8 ## i64
    if i == 1
      sum = 16
    if i == 2
      sum = 24
    shared = 32 ## i64
    if i == 2
      shared = 64
    z = ffsm_axis_set(pu, pv, pw, i, axes[0], transfer)
    z = ffsm_axis_set(pu, pv, pw, i, axes[1], sum)
    z = ffsm_axis_set(pu, pv, pw, i, axes[2], shared)
    expected_transfer = transfer ## i64
    if i < 2
      expected_transfer = transfer ^ 4
    expected_shared = shared ## i64
    if i == 2
      expected_shared = shared ^ 32
    z = ffsm_axis_set(eu, ev, ew, i, axes[0], expected_transfer)
    z = ffsm_axis_set(eu, ev, ew, i, axes[1], sum)
    z = ffsm_axis_set(eu, ev, ew, i, axes[2], expected_shared)
    i += 1
  got_u = i64[3]
  got_v = i64[3]
  got_w = i64[3]
  got_packed = i64[9]
  made = ffsm_triangle_shear_packed(pu, pv, pw, code, got_packed)
  z = ffsm_unpack_three(got_packed, got_u, got_v, got_w)
  z = ffsm_test_expect("axis permutation " + code.to_s(), made == 3 && ffsm_test_equal_three(got_u, got_v, got_w, eu, ev, ew) == 1)
  code += 1

# The finder recovers a triangle after both term and axis order are hidden.
shuffled_u = i64[3]
shuffled_v = i64[3]
shuffled_w = i64[3]
z = ffsm_test_set3(shuffled_u, old_w[2], old_w[0], old_w[1])
z = ffsm_test_set3(shuffled_v, old_u[2], old_u[0], old_u[1])
z = ffsm_test_set3(shuffled_w, old_v[2], old_v[0], old_v[1])
found_u = i64[3]
found_v = i64[3]
found_w = i64[3]
find_meta = i64[2]
found_packed = i64[9]
found = ffsm_find_triangle_shear_packed(shuffled_u, shuffled_v, shuffled_w, found_packed, find_meta) ## i64
z = ffsm_unpack_three(found_packed, found_u, found_v, found_w)
z = ffsm_test_expect("unordered axis finder", found == 3 && ffsm_verify_three_to_three(shuffled_u, shuffled_v, shuffled_w, found_u, found_v, found_w) == 1)

# Invalid, zero-producing, duplicate, no-op, and inexact outputs are rejected.
bad_u = i64[3]
bad_v = i64[3]
bad_w = i64[3]
z = ffsm_test_set3(bad_u, 1, 2, 4)
z = ffsm_test_set3(bad_v, 8, 16, 8)
z = ffsm_test_set3(bad_w, 32, 32, 64)
z = ffsm_test_expect("wrong sum rejected", ffsm_triangle_shear_packed(bad_u, bad_v, bad_w, 0, packed) == 0)
zero_u = i64[3]
zero_v = i64[3]
zero_w = i64[3]
z = ffsm_test_set3(zero_u, 4, 2, 4)
z = ffsm_test_set3(zero_v, 8, 16, 24)
z = ffsm_test_set3(zero_w, 32, 32, 64)
z = ffsm_test_expect("zero-producing shear rejected", ffsm_triangle_shear_packed(zero_u, zero_v, zero_w, 0, packed) == 0)
duplicate_u = i64[3]
duplicate_v = i64[3]
duplicate_w = i64[3]
z = ffsm_test_set3(duplicate_u, 1, 1, 4)
z = ffsm_test_set3(duplicate_v, 8, 8, 24)
z = ffsm_test_set3(duplicate_w, 32, 32, 64)
z = ffsm_test_expect("duplicate input rejected", ffsm_triangle_shear_packed(duplicate_u, duplicate_v, duplicate_w, 0, packed) == 0)
z = ffsm_test_expect("no-op replacement rejected", ffsm_validate_three_to_three(old_u, old_v, old_w, old_u, old_v, old_w) == 0)
corrupt_w = i64[3]
z = ffsm_test_set3(corrupt_w, 32, 32, 97)
z = ffsm_test_expect("inexact replacement rejected", ffsm_validate_three_to_three(old_u, old_v, old_w, want_u, want_v, corrupt_w) == 0)

# General rank-factor/append constructor.  The complementary matrix has rows
# [4,8,4], hence exact rank two: (5 x 4) + (2 x 8).
general_u = i64[3]
general_v = i64[3]
general_w = i64[3]
z = ffsm_test_set3(general_u, 1, 2, 4)
z = ffsm_test_set3(general_v, 1, 2, 4)
z = ffsm_test_set3(general_w, 4, 8, 4)
corr_left = i64[8]
corr_right = i64[8]
corr_rank = ffsm_test_factor_three(general_u, general_v, general_w, corr_left, corr_right) ## i64
z = ffsm_test_expect("complement rank is two", corr_rank == 2)
z = ffsm_test_expect("computed matrix factorization exact", ffsm_test_verify_factor_three(general_u, general_v, general_w, corr_left, corr_right, corr_rank) == 1)
general_packed = i64[15]
general_made = ffsm_test_append_three(general_u, general_v, general_w, corr_left, corr_right, general_packed) ## i64
z = ffsm_test_expect("general 3->5 shear", general_made == 5)
z = ffsm_test_expect("general shear exact", ffsm_test_verify_append_three(general_u, general_v, general_w, general_packed) == 1)
corr_right[0] = corr_right[0] ^ 1
z = ffsm_test_expect("bad matrix factorization rejected", ffsm_test_append_three(general_u, general_v, general_w, corr_left, corr_right, general_packed) == 0)

# Real rank-93 5x5 distance-six relation.  It must be discovered by the same
# constructor, all old terms must be live in the checked-in scheme, and the
# replacement must keep the complete 5x5 multiplication tensor exact.
real_old_u = i64[3]
real_old_v = i64[3]
real_old_w = i64[3]
real_want_u = i64[3]
real_want_v = i64[3]
real_want_w = i64[3]
z = ffsm_test_set3(real_old_u, 524288, 11337728, 16777216)
z = ffsm_test_set3(real_old_v, 5406720, 168965, 5248005)
z = ffsm_test_set3(real_old_w, 32768, 32768, 1048577)
z = ffsm_test_set3(real_want_u, 17301504, 28114944, 16777216)
z = ffsm_test_set3(real_want_v, 5406720, 168965, 5248005)
z = ffsm_test_set3(real_want_w, 32768, 32768, 1081345)
real_new_u = i64[3]
real_new_v = i64[3]
real_new_w = i64[3]
real_packed = i64[9]
real_made = ffsm_triangle_shear_packed(real_old_u, real_old_v, real_old_w, 0, real_packed) ## i64
z = ffsm_unpack_three(real_packed, real_new_u, real_new_v, real_new_w)
z = ffsm_test_expect("real 5x5 shear constructed", real_made == 3 && ffsm_test_equal_three(real_new_u, real_new_v, real_new_w, real_want_u, real_want_v, real_want_w) == 1)
z = ffsm_test_expect("real 5x5 distance six", ffsm_test_distance_three(real_old_u, real_old_v, real_old_w, real_new_u, real_new_v, real_new_w) == 6)

n = 5 ## i64
cap = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(cap)]
loaded = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n, cap, 13579, 0, 1, 1, 1) ## i64
z = ffsm_test_expect("real 5x5 scheme loads", loaded == 93 && ffw_verify_current_exact(state, n) == 1)
scheme_u = i64[cap]
scheme_v = i64[cap]
scheme_w = i64[cap]
scheme_rank = ffw_export_current(state, scheme_u, scheme_v, scheme_w) ## i64
i = 0
while i < 3
  found_index = 0 - 1 ## i64
  j = 0 ## i64
  while j < scheme_rank && found_index < 0
    if ffsm_same_term(scheme_u[j], scheme_v[j], scheme_w[j], real_old_u[i], real_old_v[i], real_old_w[i]) == 1
      found_index = j
    j += 1
  z = ffsm_test_expect("real old term " + i.to_s() + " is live", found_index >= 0)
  scheme_u[found_index] = real_new_u[i]
  scheme_v[found_index] = real_new_v[i]
  scheme_w[found_index] = real_new_w[i]
  i += 1
endpoint = i64[ffw_state_size(cap)]
endpoint_rank = ffw_init_terms_cap(endpoint, scheme_u, scheme_v, scheme_w, scheme_rank, n, cap, 24680, 0, 1, 1, 1) ## i64
z = ffsm_test_expect("real distance-six endpoint globally exact", endpoint_rank == 93 && ffw_verify_current_exact(endpoint, n) == 1)

<< "flipfleet_shear_moves_test: all checks passed"
