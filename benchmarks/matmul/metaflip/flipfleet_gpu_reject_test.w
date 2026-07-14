use flipfleet_gpu_reject

-> ffgrt_expect(label, condition)
  if !condition
    << "FAIL " + label
    exit(1)
  1

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
seed = i64[size]
rank = ffw_init_naive_cap(seed, n, cap, 17, 4, 2, 1000, 250) ## i64
z = ffgrt_expect("naive exact seed", rank == 27 && ffw_verify_best_exact(seed, n) == 1) ## i64

seed_path = "/tmp/flipfleet_gpu_reject_test_seed.txt"
output_path = "/tmp/flipfleet_gpu_reject_test_output.txt"
z = ffgrt_expect("seed dump", ffw_dump_best(seed, seed_path) == 27)
seed_raw = read_file(seed_path)

# Change only the first naive term's W factor from C[0,0] to C[0,1].  The
# candidate remains structurally valid rank 27 but its first tensor syndrome
# coordinate is (A[0,0], B[0,0], C[0,0]).
lines = seed_raw.split("\n")
candidate_raw = "27 999\n"
i = 0 ## i64
while i < 27
  parts = lines[i + 1].split(" ")
  w = parts[2] ## String
  if i == 0
    w = "2"
  candidate_raw = candidate_raw + parts[0] + " " + parts[1] + " " + w + "\n"
  i += 1

z = ffgrt_expect("sidecar clear", ffgr_clear_worker_sidecars(output_path) == 1)
candidate_path = ffgr_worker_candidate_path(output_path)
worker_seed_path = ffgr_worker_seed_path(output_path)
worker_meta_path = ffgr_worker_meta_path(output_path)
candidate_written = write_file(candidate_path, candidate_raw)
seed_written = write_file(worker_seed_path, seed_raw)
worker_meta = "schema=1\nworker=generic-cal2zone\nworker_nonce=7\nworker_round=3\nseed_rank=49\nnominal_rank=27\nexact_error=1\n"
meta_written = write_file(worker_meta_path, worker_meta)
z = ffgrt_expect("worker sidecars", candidate_written && seed_written && meta_written)

rejected = i64[size]
loaded = ffw_load_scheme_cap(rejected, candidate_path, n, cap, 23, 4, 2, 1000, 250) ## i64
z = ffgrt_expect("candidate rejected", loaded < 0)
z = ffgrt_expect("nominal rank parsed", ffgr_nominal_rank(candidate_raw) == 27)
exact_error = ffgr_candidate_exact_error(rejected, n, 27) ## i64
z = ffgrt_expect("first syndrome encoded", exact_error == 1)
z = ffgrt_expect("syndrome coordinate", ffgr_error_ai(exact_error, n) == 0 && ffgr_error_bi(exact_error, n) == 0 && ffgr_error_ci(exact_error, n) == 0)
z = ffgrt_expect("syndrome parity", ffgr_error_want(exact_error, n) == 1)
z = ffgrt_expect("metadata parser", ffgr_meta_value(worker_meta, "worker") == "generic-cal2zone" && ffgr_meta_i64(worker_meta, "worker_nonce", -1) == 7)

run_tag = "gpu-reject-test"
counter = 3 ## i64
slot = 11 ## i64
nonce = 42 ## i64
preserved = ffgr_preserve(run_tag, n, counter, slot, 10, 4, nonce, 26, "generic-cal2zone", 7, 3, 49, 27, 1, exact_error, seed_raw, candidate_raw) ## i64
z = ffgrt_expect("bundle preserved", preserved == 1)
frozen_meta_path = ffgr_bundle_meta_path(run_tag, n, counter, slot, nonce)
frozen_meta = read_file(frozen_meta_path)
z = ffgrt_expect("bundle metadata", frozen_meta.include?("internal_rejects=3") && frozen_meta.include?("launch_nonce=42") && frozen_meta.include?("target_rank=26") && frozen_meta.include?("mismatch_ai=0") && frozen_meta.include?("mismatch_want=1") && frozen_meta.include?("mismatch_got=0"))
z = ffgrt_expect("bundle seed bytes", read_file(ffgr_bundle_prefix(run_tag, n, counter, slot, nonce) + ".seed") == seed_raw)
z = ffgrt_expect("bundle candidate bytes", read_file(ffgr_bundle_prefix(run_tag, n, counter, slot, nonce) + ".candidate") == candidate_raw)
summary = read_file(ffgr_summary_path(run_tag, n))
z = ffgrt_expect("counter summary", summary.include?("internal_rejects=3") && summary.include?(frozen_meta_path))
log_line = ffgr_log_line(counter, slot, 10, 4, nonce, 26, 27, 1, exact_error, preserved, frozen_meta_path)
z = ffgrt_expect("explicit log counter", log_line.include?("GPU_INTERNAL_REJECT internal_rejects=3") && log_line.include?("nonce=42"))

<< "flipfleet_gpu_reject_test: all checks passed"
