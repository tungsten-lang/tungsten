use flipfleet_syndrome_repair

-> ffsrt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

-> ffsrt_copy(source, target, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target[i] = source[i]
    i += 1
  count

-> ffsrt_exact_terms(us, vs, ws, rank, n, capacity) (i64[] i64[] i64[] i64 i64 i64) i64
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, us, vs, ws, rank, n, capacity, 991, 4, 2, 1000, 250) ## i64
  if loaded == rank && ffw_verify_current_exact(state, n) == 1
    return 1
  0

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
base = i64[state_size]
base_rank = ffw_init_naive_cap(base, n, capacity, 971, 4, 2, 1000, 250) ## i64
z = ffsrt_expect("naive source exact", base_rank == 27 && ffw_verify_current_exact(base, n) == 1) ## i64
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(base, base_u, base_v, base_w)
z = ffsrt_expect("naive source exported", z == base_rank && base_u[0] == 1 && base_v[0] == 1 && base_w[0] == 1)

words = ffsr_tensor_words(n) ## i64
dim = n * n ## i64
syndrome = i64[words]
a_slices = i64[dim]
b_slices = i64[dim]
c_slices = i64[dim]
syndrome_meta = i64[10]
weight = ffsr_build_syndrome(base_u, base_v, base_w, base_rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
z = ffsrt_expect("exact source has zero syndrome", weight == 0 && syndrome_meta[9] == 0)

# One term's W factor changes 1 -> 2.  This is two one-bit edits on one axis;
# the full syndrome contains the deleted and inserted tensor coefficients.
bad_u = i64[capacity]
bad_v = i64[capacity]
bad_w = i64[capacity]
z = ffsrt_copy(base_u, bad_u, base_rank)
z = ffsrt_copy(base_v, bad_v, base_rank)
z = ffsrt_copy(base_w, bad_w, base_rank)
bad_w[0] = bad_w[0] ^ 3
weight = ffsr_build_syndrome(bad_u, bad_v, bad_w, base_rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta)
z = ffsrt_expect("full syndrome weight", weight == 2 && syndrome_meta[9] == 1)
z = ffsrt_expect("all slice families measured", syndrome_meta[3] == 1 && syndrome_meta[4] == 1 && syndrome_meta[5] == 2 && a_slices[0] == 2 && b_slices[0] == 2 && c_slices[0] == 1 && c_slices[1] == 1)

rejected = i64[state_size]
loaded_bad = ffw_init_terms_cap(rejected, bad_u, bad_v, bad_w, base_rank, n, capacity, 977, 4, 2, 1000, 250) ## i64
z = ffsrt_expect("worker retains structurally valid reject", loaded_bad < 0 && ffw_current_rank(rejected) == base_rank && ffgr_candidate_exact_error(rejected, n, base_rank) == 1)
current_meta = i64[10]
current_weight = ffsr_current_syndrome(rejected, n, syndrome, a_slices, b_slices, c_slices, current_meta) ## i64
z = ffsrt_expect("current-view syndrome replay", current_weight == 2 && current_meta[9] == 1)

z = ffsrt_expect("edit portfolios enumerated", ffsr_edit_count(base_rank, n, 0) == 729 && ffsr_edit_count(base_rank, n, 3) == 243 && ffsr_edit_count(base_rank, n, 4) == 243)
z = ffsrt_expect("all-axis budget is larger", ffsr_work_words(base_rank, n, 0) > ffsr_work_words(base_rank, n, 3))

repair_u = i64[capacity]
repair_v = i64[capacity]
repair_w = i64[capacity]
repair_meta = i64[16]
guarded = ffsr_try_repair(bad_u, bad_v, bad_w, base_rank, n, 3, 1, repair_u, repair_v, repair_w, capacity, repair_meta) ## i64
z = ffsrt_expect("explicit work budget guards allocation", guarded == 0 && repair_meta[11] == 0 - 2)

repaired = ffsr_try_repair(bad_u, bad_v, bad_w, base_rank, n, 3, 1000000, repair_u, repair_v, repair_w, capacity, repair_meta) ## i64
z = ffsrt_expect("two-edit W repair solved", repaired == base_rank && repair_meta[0] == 2 && repair_meta[4] == 2 && repair_meta[5] == 1 && repair_meta[6] == 0)
z = ffsrt_expect("two-edit W repair exact-gated", repair_meta[8] == 1 && ffsrt_exact_terms(repair_u, repair_v, repair_w, repaired, n, capacity) == 1)

# Mixed axes on different terms remain linear.  Striped mode 4 assigns U/V/W
# to terms 0/1/2 respectively, so every possible solution is algebraically
# safe before still passing through the independent full gate.
mixed_u = i64[capacity]
mixed_v = i64[capacity]
mixed_w = i64[capacity]
z = ffsrt_copy(base_u, mixed_u, base_rank)
z = ffsrt_copy(base_v, mixed_v, base_rank)
z = ffsrt_copy(base_w, mixed_w, base_rank)
mixed_u[0] = mixed_u[0] ^ 256
mixed_v[4] = mixed_v[4] ^ 1
mixed_w[8] = mixed_w[8] ^ 1
mixed_meta = i64[16]
mixed_rank = ffsr_try_repair(mixed_u, mixed_v, mixed_w, base_rank, n, 4, 1000000, repair_u, repair_v, repair_w, capacity, mixed_meta) ## i64
z = ffsrt_expect("striped mixed-axis repair solved", mixed_rank == base_rank && mixed_meta[4] == 3 && mixed_meta[6] == 0)
z = ffsrt_expect("striped mixed-axis repair exact", mixed_meta[8] == 1 && ffsrt_exact_terms(repair_u, repair_v, repair_w, mixed_rank, n, capacity) == 1)

# Append a spurious term.  U-only elimination can toggle its two U bits to
# zero; materialization compacts the zero rank-one term and recovers rank 27.
base_again = ffsr_build_syndrome(base_u, base_v, base_w, base_rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
z = ffsrt_expect("repair inputs remain immutable", base_again == 0)
drop_u = i64[capacity]
drop_v = i64[capacity]
drop_w = i64[capacity]
z = ffsrt_copy(base_u, drop_u, base_rank)
z = ffsrt_copy(base_v, drop_v, base_rank)
z = ffsrt_copy(base_w, drop_w, base_rank)
drop_base_weight = ffsr_build_syndrome(drop_u, drop_v, drop_w, base_rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
z = ffsrt_expect("rank-drop source copy exact", drop_base_weight == 0)
drop_u[base_rank] = 3
drop_v[base_rank] = 17
drop_w[base_rank] = 257
drop_rank = base_rank + 1 ## i64
drop_weight_direct = ffsr_build_syndrome(drop_u, drop_v, drop_w, drop_rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
z = ffsrt_expect("spurious rank-one syndrome measured", drop_weight_direct == 8)
extra_probe = i64[words]
extra_a = i64[dim]
extra_b = i64[dim]
extra_c = i64[dim]
extra_meta = i64[10]
extra_z = ffsr_clear(extra_probe, 0, words) ## i64
extra_z = ffsr_xor_outer(extra_probe, 0, 3, 17, 257, n)
extra_weight = ffsr_measure(extra_probe, n, extra_a, extra_b, extra_c, extra_meta) ## i64
diff_probe = i64[words]
extra_z = ffsr_copy(syndrome, 0, diff_probe, 0, words)
extra_z = ffsr_xor(extra_probe, 0, diff_probe, 0, words)
diff_meta = i64[10]
diff_weight = ffsr_measure(diff_probe, n, extra_a, extra_b, extra_c, diff_meta) ## i64
z = ffsrt_expect("syndrome equals planted outer", extra_weight == 8 && diff_weight == 0)
drop_meta = i64[16]
dropped = ffsr_try_repair(drop_u, drop_v, drop_w, drop_rank, n, 1, 1000000, repair_u, repair_v, repair_w, capacity, drop_meta) ## i64
z = ffsrt_expect("zero-factor repair drops spurious term", dropped == base_rank && drop_meta[4] == 2 && drop_meta[5] == 1)
z = ffsrt_expect("rank-drop repair exact", drop_meta[8] == 1 && ffsrt_exact_terms(repair_u, repair_v, repair_w, dropped, n, capacity) == 1)

# Exercise the real preservation boundary: raw invalid candidate + metadata
# commit marker -> retained worker current view -> complete syndrome.
candidate_path = "/tmp/flipfleet_syndrome_repair_test.candidate"
metadata_path = "/tmp/flipfleet_syndrome_repair_test.meta"
candidate_raw = base_rank.to_s() + "\n"
i = 0 ## i64
while i < base_rank
  candidate_raw = candidate_raw + bad_u[i].to_s() + " " + bad_v[i].to_s() + " " + bad_w[i].to_s() + "\n"
  i += 1
wrote_candidate = write_file(candidate_path, candidate_raw)
metadata_raw = "schema=1\nkind=gpu_internal_reject\ntensor=3x3\nnominal_rank=27\nworker_exact_error=1\ncoordinator_exact_error=1\ncandidate_path=" + candidate_path + "\n"
wrote_metadata = write_file(metadata_path, metadata_raw)
z = ffsrt_expect("synthetic replay files written", wrote_candidate && wrote_metadata)
replay = i64[state_size]
replay_info = i64[5]
replay_rank = ffsr_load_preserved(replay, metadata_path, n, capacity, 983, replay_info) ## i64
z = ffsrt_expect("preserved reject loads", replay_rank == base_rank && replay_info[0] == base_rank && replay_info[1] == 1 && replay_info[4] < 0)
replay_meta = i64[16]
replay_repaired = ffsr_try_repair_current(replay, n, 3, 1000000, repair_u, repair_v, repair_w, capacity, replay_meta) ## i64
z = ffsrt_expect("preserved reject repairs exactly", replay_repaired == base_rank && replay_meta[0] == 2 && replay_meta[8] == 1)

<< "PASS flipfleet syndrome repair planted=3 rank_drop=28->27 replay=1"
