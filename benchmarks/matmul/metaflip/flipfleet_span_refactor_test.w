use metaflip_worker
use flipfleet_span_refactor

-> span_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> span_check_move(name, su, sv, sw, k, want) (String i64[] i64[] i64[] i64 i64) i64
  out_u = i64[4]
  out_v = i64[4]
  out_w = i64[4]
  meta = i64[12]
  found = ffsr_find_terms(su, sv, sw, k, want, out_u, out_v, out_w, meta) ## i64
  z = span_expect(name + " found", found == want) ## i64
  z = span_expect(name + " exact local identity", ffsr_verify_local_replacement(su, sv, sw, k, out_u, out_v, out_w, found) == 1)
  z = span_expect(name + " distinct nonzero output", ffsr_output_well_formed(out_u, out_v, out_w, found) == 1)
  if k == want
    z = span_expect(name + " rejects original permutations", ffsr_terms_same_set(su, sv, sw, k, out_u, out_v, out_w, found) == 0)
  found

# 3 -> 2: merge a planted one-axis split while retaining a third term.
su32 = i64[4]
sv32 = i64[4]
sw32 = i64[4]
su32[0] = 1
sv32[0] = 4
sw32[0] = 8
su32[1] = 2
sv32[1] = 4
sw32[1] = 8
su32[2] = 4
sv32[2] = 2
sw32[2] = 1
z = span_expect("3->2 supported", ffsr_move_supported(3, 2) == 1) ## i64
z = span_expect("3->2 planted", span_check_move("3->2", su32, sv32, sw32, 3, 2) == 2)

# 3 <-> 3: a shared-U two-term flip plus an unchanged third term.
su33 = i64[4]
sv33 = i64[4]
sw33 = i64[4]
su33[0] = 1
sv33[0] = 1
sw33[0] = 1
su33[1] = 1
sv33[1] = 2
sw33[1] = 2
su33[2] = 4
sv33[2] = 4
sw33[2] = 4
z = span_expect("3<->3 planted", span_check_move("3<->3", su33, sv33, sw33, 3, 3) == 3)

# 3 -> 4: split the first term into two factors from the selected U span.
su34 = i64[4]
sv34 = i64[4]
sw34 = i64[4]
su34[0] = 3
sv34[0] = 4
sw34[0] = 8
su34[1] = 1
sv34[1] = 2
sw34[1] = 1
su34[2] = 4
sv34[2] = 1
sw34[2] = 2
z = span_expect("3->4 planted", span_check_move("3->4", su34, sv34, sw34, 3, 4) == 4)

# 4 -> 3: the reverse planted split, with two retained terms.
su43 = i64[4]
sv43 = i64[4]
sw43 = i64[4]
su43[0] = 1
sv43[0] = 4
sw43[0] = 8
su43[1] = 2
sv43[1] = 4
sw43[1] = 8
su43[2] = 4
sv43[2] = 2
sw43[2] = 1
su43[3] = 8
sv43[3] = 1
sw43[3] = 2
z = span_expect("4->3 supported", ffsr_move_supported(4, 3) == 1) ## i64
z = span_expect("4->3 planted", span_check_move("4->3", su43, sv43, sw43, 4, 3) == 3)

# 4 <-> 4: a shared-U flip plus two unrelated terms.  This exercises the
# complete pair/pair chain rather than a hand-coded flip special case.
su44 = i64[4]
sv44 = i64[4]
sw44 = i64[4]
su44[0] = 1
sv44[0] = 1
sw44[0] = 1
su44[1] = 1
sv44[1] = 2
sw44[1] = 2
su44[2] = 2
sv44[2] = 4
sw44[2] = 4
su44[3] = 4
sv44[3] = 1
sw44[3] = 8
z = span_expect("4<->4 planted", span_check_move("4<->4", su44, sv44, sw44, 4, 4) == 4)

# Full four-dimensional axis spans occupy exactly 64 signature bits.  The
# selected diagonal includes coordinate (3,3,3), proving that bit 63 survives
# in the signed i64 representation rather than being truncated.
su64 = i64[4]
sv64 = i64[4]
sw64 = i64[4]
i = 0 ## i64
while i < 4
  su64[i] = 1 << i
  sv64[i] = 1 << i
  sw64[i] = 1 << i
  i += 1
cu64 = i64[3375]
cv64 = i64[3375]
cw64 = i64[3375]
sig64 = i64[3375]
original64 = i64[4]
meta64 = i64[12]
count64 = ffsr_build_candidates(su64, sv64, sw64, 4, cu64, cv64, cw64, sig64, original64, meta64) ## i64
z = span_expect("full span enumerates 3375 candidates", count64 == 3375)
z = span_expect("full span uses exactly 64 signature bits", meta64[0] == 4 && meta64[1] == 4 && meta64[2] == 4 && meta64[3] == 64)
z = span_expect("exact target retains signature bit 63", ((meta64[5] >> 63) & 1) == 1)
z = span_expect("worst pair count is bounded", meta64[6] == 5693625 && ffsr_pair_table_capacity(count64) == 4194304)
ids64 = i64[4]
# Drive the full candidate table with a planted shared-U flip whose first
# term owns coordinate bit 63.  The original diagonal itself may be locally
# identifiable, so use this explicit nontrivial target for the MITM test.
mitm64_u = i64[4]
mitm64_v = i64[4]
mitm64_w = i64[4]
mitm64_u[0] = 8
mitm64_v[0] = 8
mitm64_w[0] = 8
mitm64_u[1] = 8
mitm64_v[1] = 4
mitm64_w[1] = 4
mitm64_u[2] = 1
mitm64_v[2] = 1
mitm64_w[2] = 1
mitm64_u[3] = 2
mitm64_v[3] = 2
mitm64_w[3] = 2
mitm64_original = i64[4]
mitm64_target = 0 ## i64
i = 0
while i < 4
  mitm64_original[i] = ffsr_find_candidate_term(cu64, cv64, cw64, count64, mitm64_u[i], mitm64_v[i], mitm64_w[i])
  mitm64_target = mitm64_target ^ sig64[mitm64_original[i]]
  i += 1
z = span_expect("64-bit MITM target includes bit 63", ((mitm64_target >> 63) & 1) == 1)
found64 = ffsr_find_ids(sig64, count64, mitm64_target, mitm64_original, 4, 4, ids64, meta64) ## i64
out64_u = i64[4]
out64_v = i64[4]
out64_w = i64[4]
made64 = ffsr_materialize_ids(cu64, cv64, cw64, count64, ids64, found64, out64_u, out64_v, out64_w) ## i64
z = span_expect("64-bit pair MITM finds an alternative", found64 == 4 && made64 == 4)
z = span_expect("64-bit pair MITM identity is exact", ffsr_verify_local_replacement(mitm64_u, mitm64_v, mitm64_w, 4, out64_u, out64_v, out64_w, 4) == 1)

# Real-seed smoke: find a same-rank span refactor around a known flippable
# pair in the exact rank-23 3x3 scheme, then splice and exhaustively verify it.
n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
real_state = i64[state_size]
rank = ffw_load_scheme_cap(real_state, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 314159, 4, 2, 1000, 250) ## i64
z = span_expect("real rank-23 seed loads", rank == 23 && ffw_verify_current_exact(real_state, n) == 1)
selected_real = i64[4]
selected_real[0] = 3
selected_real[1] = 15
selected_real[2] = 0
real_out_u = i64[4]
real_out_v = i64[4]
real_out_w = i64[4]
real_meta = i64[12]
real_found = ffsr_find_current(real_state, selected_real, 3, 3, real_out_u, real_out_v, real_out_w, real_meta) ## i64
z = span_expect("real seed same-rank replacement found", real_found == 3)
real_applied = ffsr_apply_current(real_state, selected_real, 3, real_out_u, real_out_v, real_out_w, real_found) ## i64
z = span_expect("real seed replacement splices exactly", real_applied == 23 && ffw_verify_current_exact(real_state, n) == 1)

# Build an exact rank-24 shoulder by splitting one live term, then use the
# direct splice gate to merge it back to rank 23.  This exercises a genuine
# rank-reducing full-tensor edit, not merely a local signature comparison.
base_state = i64[state_size]
base_rank = ffw_load_scheme_cap(base_state, "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt", n, capacity, 271828, 4, 2, 1000, 250) ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
exported = ffw_export_current(base_state, base_u, base_v, base_w) ## i64
split_index = 0 - 1 ## i64
i = 0
while i < exported && split_index < 0
  if ffw_popcount(base_u[i]) >= 2
    split_index = i
  i += 1
z = span_expect("rank-23 seed has a splittable U factor", base_rank == 23 && split_index >= 0)
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
shoulder_rank = 0 ## i64
i = 0
while i < exported
  if i != split_index
    shoulder_u[shoulder_rank] = base_u[i]
    shoulder_v[shoulder_rank] = base_v[i]
    shoulder_w[shoulder_rank] = base_w[i]
    shoulder_rank += 1
  i += 1
split_u1 = base_u[split_index] & (0 - base_u[split_index]) ## i64
split_u2 = base_u[split_index] ^ split_u1 ## i64
shoulder_u[shoulder_rank] = split_u1
shoulder_v[shoulder_rank] = base_v[split_index]
shoulder_w[shoulder_rank] = base_w[split_index]
shoulder_rank += 1
shoulder_u[shoulder_rank] = split_u2
shoulder_v[shoulder_rank] = base_v[split_index]
shoulder_w[shoulder_rank] = base_w[split_index]
shoulder_rank += 1
shoulder_state = i64[state_size]
loaded_shoulder = ffw_init_terms_cap(shoulder_state, shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, capacity, 161803, 4, 2, 1000, 250) ## i64
z = span_expect("planted rank-24 shoulder is exact", loaded_shoulder == 24 && ffw_verify_current_exact(shoulder_state, n) == 1)

selected_drop = i64[4]
selected_drop[0] = shoulder_rank - 2
selected_drop[1] = shoulder_rank - 1
selected_drop[2] = 0
drop_out_u = i64[4]
drop_out_v = i64[4]
drop_out_w = i64[4]
drop_out_u[0] = base_u[split_index]
drop_out_v[0] = base_v[split_index]
drop_out_w[0] = base_w[split_index]
drop_out_u[1] = shoulder_u[0]
drop_out_v[1] = shoulder_v[0]
drop_out_w[1] = shoulder_w[0]
drop_rank = ffsr_apply_current(shoulder_state, selected_drop, 3, drop_out_u, drop_out_v, drop_out_w, 2) ## i64
z = span_expect("rank-24 shoulder merges to exact rank 23", drop_rank == 23 && ffw_verify_current_exact(shoulder_state, n) == 1)

# No-op and invalid replacements are rejected.  The invalid identity reaches
# the exhaustive verifier, then proves rollback by re-verifying the old state.
selected_bad = i64[4]
selected_bad[0] = 0
selected_bad[1] = 1
selected_bad[2] = 2
bad_u = i64[4]
bad_v = i64[4]
bad_w = i64[4]
z = ffsr_capture_current(shoulder_state, selected_bad, 3, bad_u, bad_v, bad_w)
no_op = ffsr_apply_current(shoulder_state, selected_bad, 3, bad_u, bad_v, bad_w, 3) ## i64
z = span_expect("exact no-op permutation is rejected", no_op < 0 && shoulder_state[6] == 23)
bad_u[0] = bad_u[0] ^ (1 << 8)
if bad_u[0] == 0
  bad_u[0] = 1
invalid = ffsr_apply_current(shoulder_state, selected_bad, 3, bad_u, bad_v, bad_w, 3) ## i64
z = span_expect("invalid splice rolls back exactly", invalid < 0 && shoulder_state[6] == 23 && ffw_verify_current_exact(shoulder_state, n) == 1)

# A real 5x5 rank-93 relation that is not a compatible pair flip.  All three
# old terms change (term-set distance six): the first two share W, their V
# factors sum to the third V, and the coupled U/U/W shear cancels exactly.
n5 = 5 ## i64
cap5 = ffw_default_capacity(n5) ## i64
size5 = ffw_state_size(cap5) ## i64
state5 = i64[size5]
rank5 = ffw_load_scheme_cap(state5, "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", n5, cap5, 424243, 4, 2, 1000, 250) ## i64
z = span_expect("real 5x5 rank-93 seed loads", rank5 == 93 && ffw_verify_current_exact(state5, n5) == 1)
old5_u = i64[4]
old5_v = i64[4]
old5_w = i64[4]
old5_u[0] = 524288
old5_v[0] = 5406720
old5_w[0] = 32768
old5_u[1] = 11337728
old5_v[1] = 168965
old5_w[1] = 32768
old5_u[2] = 16777216
old5_v[2] = 5248005
old5_w[2] = 1048577
new5_u = i64[4]
new5_v = i64[4]
new5_w = i64[4]
new5_u[0] = 17301504
new5_v[0] = 5406720
new5_w[0] = 32768
new5_u[1] = 28114944
new5_v[1] = 168965
new5_w[1] = 32768
new5_u[2] = 16777216
new5_v[2] = 5248005
new5_w[2] = 1081345
z = span_expect("real 5x5 non-pair relation is locally exact", ffsr_verify_local_replacement(old5_u, old5_v, old5_w, 3, new5_u, new5_v, new5_w, 3) == 1)
all5_u = i64[cap5]
all5_v = i64[cap5]
all5_w = i64[cap5]
count5 = ffw_export_current(state5, all5_u, all5_v, all5_w) ## i64
selected5 = i64[4]
i = 0
while i < 3
  selected5[i] = ffsr_find_candidate_term(all5_u, all5_v, all5_w, count5, old5_u[i], old5_v[i], old5_w[i])
  i += 1
z = span_expect("real 5x5 non-pair terms are live", selected5[0] >= 0 && selected5[1] >= 0 && selected5[2] >= 0)
applied5 = ffsr_apply_current(state5, selected5, 3, new5_u, new5_v, new5_w, 3) ## i64
z = span_expect("real 5x5 distance-six splice stays exact", applied5 == 93 && ffw_verify_current_exact(state5, n5) == 1)

z = span_expect("unsupported move rejected", ffsr_move_supported(4, 2) == 0 && ffsr_move_supported(4, 5) == 0)

<< "flipfleet_span_refactor_test: all checks passed"
