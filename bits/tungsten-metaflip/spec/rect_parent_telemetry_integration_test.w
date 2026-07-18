use ../lib/metaflip/rect/portfolio

failures_count = 0 ## i64

-> rect_parent_integration_expect(label, condition) (String bool) i64
  if condition
    << "PASS " + label
    return 0
  << "FAIL " + label
  1

tag = "rect_parent_telemetry_" + ccall("__w_clock_ms").to_s()
runtime_root = __DIR__ + "/../lib/metaflip"
best_base = "/tmp/" + tag + "_best"
status_path = "/tmp/" + tag + "_status"

# This embedding test has no Metaflip CLI main to re-exec, so select the
# documented in-process fallback. The production CLI passes its executable
# path and is covered by rect_process_isolation_test.w.
result = ffrpo_run("2x5x6,4x4x5", runtime_root, "", best_base, 1, status_path, 1, tag, 2, 20000, 2, 0, 1, 4, 4, 0, 0, "adaptive", 100, 1, "", 0, 1, 0, 0, 0, "") ## i64
body = read_file(status_path)
failures_count += rect_parent_integration_expect("two-epoch portfolio succeeds", result == 0 && body != nil && body.size() > 0)

if body == nil
  body = ""
lines = body.split("\n")
header = ""
if lines.size() > 0
  header = lines[0]
total_moves = ffrpo_status_i64(header, "total_moves", 0 - 1) ## i64
total_cpu = ffrpo_status_i64(header, "total_cpu_moves", 0 - 1) ## i64
total_gpu = ffrpo_status_i64(header, "total_gpu_moves", 0 - 1) ## i64
total_mitm_attempts = ffrpo_status_i64(header, "total_mitm_attempts", 0 - 1) ## i64
total_mitm_pairs = ffrpo_status_i64(header, "total_mitm_pairs", 0 - 1) ## i64
total_mitm_ms = ffrpo_status_i64(header, "total_mitm_ms", 0 - 1) ## i64
total_mitm_failures = ffrpo_status_i64(header, "total_mitm_failures", 0 - 1) ## i64

shape_count = 0 ## i64
shape_moves_sum = 0 ## i64
shape_cpu_sum = 0 ## i64
shape_gpu_sum = 0 ## i64
shape_mitm_attempts_sum = 0 ## i64
shape_mitm_pairs_sum = 0 ## i64
shape_mitm_ms_sum = 0 ## i64
shape_mitm_failures_sum = 0 ## i64
i = 1 ## i64
while i < lines.size()
  line = lines[i]
  if line.starts_with?("shape=")
    shape_count += 1
    shape_moves_sum += ffrpo_status_i64(line, "moves", 0)
    shape_cpu_sum += ffrpo_status_i64(line, "cpu_moves", 0)
    shape_gpu_sum += ffrpo_status_i64(line, "gpu_moves", 0)
    shape_mitm_attempts_sum += ffrpo_status_i64(line, "mitm_attempts", 0)
    shape_mitm_pairs_sum += ffrpo_status_i64(line, "mitm_pairs", 0)
    shape_mitm_ms_sum += ffrpo_status_i64(line, "mitm_ms", 0)
    shape_mitm_failures_sum += ffrpo_status_i64(line, "mitm_failures", 0)
  i += 1

failures_count += rect_parent_integration_expect("terminal parent status is healthy", header.include?("producer_state=stopped") && header.include?("health=ok"))
failures_count += rect_parent_integration_expect("both shapes are represented", shape_count == 2)
failures_count += rect_parent_integration_expect("two epochs commit exactly once", total_moves == 80000 && shape_moves_sum == 80000)
failures_count += rect_parent_integration_expect("CPU total equals combined CPU-only work", total_cpu == total_moves && shape_cpu_sum == total_cpu)
failures_count += rect_parent_integration_expect("GPU total remains zero", total_gpu == 0 && shape_gpu_sum == 0)
failures_count += rect_parent_integration_expect("MITM totals remain zero without GPU", total_mitm_attempts == 0 && total_mitm_pairs == 0 && total_mitm_ms == 0 && total_mitm_failures == 0 && shape_mitm_attempts_sum == 0 && shape_mitm_pairs_sum == 0 && shape_mitm_ms_sum == 0 && shape_mitm_failures_sum == 0)

if failures_count != 0
  << "FAIL rectangular parent telemetry integration failures=" + failures_count.to_s()
  exit(1)

<< "PASS rectangular parent telemetry integration total=" + total_moves.to_s()
