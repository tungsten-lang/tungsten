use flipfleet_rect_gpu_reject

-> ffrgrt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

n = 2 ## i64
m = 3 ## i64
p = 4 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
state_size = ffr_state_size(capacity) ## i64
seed = i64[state_size]
rank = ffr_init_naive_cap(seed, n, m, p, capacity, 17, 4, 2, 1000, 250) ## i64
z = ffrgrt_expect("rectangular naive exact", rank == 24 && ffr_verify_best_exact(seed, n, m, p) == 1) ## i64

seed_path = "/tmp/flipfleet_rect_gpu_reject_test_seed.txt"
output_path = "/tmp/flipfleet_rect_gpu_reject_test_output.txt"
z = ffrgrt_expect("seed dump", ffr_dump_best(seed, seed_path) == 24)
seed_raw = read_file(seed_path)

# Replace the final naive term's C[1,3] bit (128) by C[1,2] (64).  For
# <2,3,4>, the first mismatch is (ai,bi,ci)=(5,11,6), flattened as 575.
# This deliberately catches accidental reuse of the square n*n decoder.
lines = seed_raw.split("\n")
candidate_raw = "24 999\n"
i = 0 ## i64
while i < 24
  parts = lines[i + 1].split(" ")
  w = parts[2] ## String
  if i == 23
    z = ffrgrt_expect("expected final W factor", w == "128")
    w = "64"
  candidate_raw = candidate_raw + parts[0] + " " + parts[1] + " " + w + "\n"
  i += 1

z = ffrgrt_expect("initial safe clear", ffrgr_clear_worker_sidecars(output_path) == 1)
candidate_path = ffgr_worker_candidate_path(output_path)
worker_seed_path = ffgr_worker_seed_path(output_path)
worker_meta_path = ffgr_worker_meta_path(output_path)

# Payloads without metadata are uncommitted orphans and may be cleared before
# an epoch.  A committed marker must instead block epoch reuse.
z = ffrgrt_expect("orphan candidate write", write_file(candidate_path, candidate_raw))
z = ffrgrt_expect("orphan is not committed", ffrgr_worker_sidecars_committed(output_path) == 0)
z = ffrgrt_expect("prepare clears orphan", ffrgr_prepare_worker_sidecars(output_path) == 1 && read_file(candidate_path) == "")

worker_meta = "schema=1\nworker=generic-cal2zone\nworker_nonce=7\nworker_round=3\nseed_rank=24\nnominal_rank=24\nnominal_density=999\nexact_error=575\n"
z = ffrgrt_expect("candidate sidecar", write_file(candidate_path, candidate_raw))
z = ffrgrt_expect("seed sidecar", write_file(worker_seed_path, seed_raw))
z = ffrgrt_expect("metadata commit marker", write_file(worker_meta_path, worker_meta))
z = ffrgrt_expect("committed marker detected", ffrgr_worker_sidecars_committed(output_path) == 1)
z = ffrgrt_expect("committed marker blocks overwrite", ffrgr_prepare_worker_sidecars(output_path) == 0 && read_file(candidate_path) == candidate_raw)

rejected = i64[state_size]
loaded = ffr_load_scheme_cap(rejected, candidate_path, n, m, p, capacity, 23, 4, 2, 1000, 250) ## i64
z = ffrgrt_expect("candidate rejected", loaded < 0)
exact_error = ffrgr_candidate_exact_error(rejected, n, m, p, 24) ## i64
z = ffrgrt_expect("rectangular syndrome", exact_error == 575)
z = ffrgrt_expect("rectangular coordinates", ffrgr_error_ai(exact_error, n, m, p) == 5 && ffrgr_error_bi(exact_error, n, m, p) == 11 && ffrgr_error_ci(exact_error, n, m, p) == 6)
z = ffrgrt_expect("rectangular mismatch parity", ffrgr_error_want(exact_error, n, m, p) == 0)

status = i64[8]
counter = ffrgr_harvest(output_path, seed_path, "rect-reject-test", n, m, p, 13, 10, 0 - 1, 42, 23, capacity, 4, 2, 1000, 250, 0, rejected, status) ## i64
z = ffrgrt_expect("committed event harvested", counter == 1 && status[0] == 1 && status[1] == 1 && status[2] == 1)
z = ffrgrt_expect("independent error retained", status[3] == 575 && status[4] == 575 && status[5] == 24)
z = ffrgrt_expect("replay byte counts", status[6] == candidate_raw.size() && status[7] == seed_raw.size())
z = ffrgrt_expect("live commit cleared first", read_file(worker_meta_path) == "" && read_file(candidate_path) == "" && read_file(worker_seed_path) == "")

prefix = ffrgr_bundle_prefix("rect-reject-test", n, m, p, 1, 13, 42)
frozen_meta = read_file(prefix + ".meta")
z = ffrgrt_expect("shape-aware metadata", frozen_meta.include?("tensor=2x3x4") && frozen_meta.include?("coordinator_exact_error=575") && frozen_meta.include?("mismatch_ai=5") && frozen_meta.include?("mismatch_bi=11") && frozen_meta.include?("mismatch_ci=6") && frozen_meta.include?("mismatch_a_row=1") && frozen_meta.include?("mismatch_a_col=2") && frozen_meta.include?("mismatch_b_row=2") && frozen_meta.include?("mismatch_b_col=3") && frozen_meta.include?("mismatch_c_row=1") && frozen_meta.include?("mismatch_c_col=2") && frozen_meta.include?("mismatch_want=0") && frozen_meta.include?("mismatch_got=1"))
z = ffrgrt_expect("seed bytes preserved", read_file(prefix + ".seed") == seed_raw)
z = ffrgrt_expect("candidate bytes preserved", read_file(prefix + ".candidate") == candidate_raw)
z = ffrgrt_expect("raw worker metadata preserved", read_file(prefix + ".worker.meta") == worker_meta)
summary = read_file(ffrgr_summary_path("rect-reject-test", n, m, p))
z = ffrgrt_expect("summary counter", summary.include?("internal_rejects=1") && summary.include?(prefix + ".meta"))

counter2 = ffrgr_harvest(output_path, seed_path, "rect-reject-test", n, m, p, 13, 10, 0 - 1, 43, 23, capacity, 4, 2, 1000, 250, counter, rejected, status) ## i64
z = ffrgrt_expect("no marker means no event", counter2 == counter && status[0] == 0)

# A failed archive write must leave the only committed evidence intact and
# prevent the next epoch from overwriting it.  The slash creates a guaranteed
# missing directory under /tmp for the synthetic archive prefix.
failure_output = "/tmp/flipfleet_rect_gpu_reject_test_failure.txt"
z = ffrgrt_expect("failure clear", ffrgr_clear_worker_sidecars(failure_output) == 1)
z = ffrgrt_expect("failure candidate", write_file(ffgr_worker_candidate_path(failure_output), candidate_raw))
z = ffrgrt_expect("failure seed", write_file(ffgr_worker_seed_path(failure_output), seed_raw))
z = ffrgrt_expect("failure commit", write_file(ffgr_worker_meta_path(failure_output), worker_meta))
failed_counter = ffrgr_harvest(failure_output, seed_path, "missing/archive", n, m, p, 13, 10, 0 - 1, 44, 23, capacity, 4, 2, 1000, 250, 1, rejected, status) ## i64
z = ffrgrt_expect("archive failure does not advance", failed_counter == 1 && status[0] == 1 && status[1] == 0 && status[2] == 0)
z = ffrgrt_expect("archive failure retains evidence", read_file(ffgr_worker_meta_path(failure_output)) == worker_meta && read_file(ffgr_worker_candidate_path(failure_output)) == candidate_raw)
z = ffrgrt_expect("retained evidence blocks reuse", ffrgr_prepare_worker_sidecars(failure_output) == 0)

<< "flipfleet_rect_gpu_reject_test: all checks passed"
