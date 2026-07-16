use ../lib/metaflip/rect/portfolio

failures_count = 0 ## i64

-> rect_parent_telemetry_expect(label, condition) (String bool) i64
  if condition
    << "PASS " + label
    return 0
  << "FAIL " + label
  1

labels = ["2x5x6", "4x4x5"]
count = labels.size() ## i64
shape_moves = i64[count]
shape_cpu_moves = i64[count]
shape_gpu_moves = i64[count]
shape_mitm_attempts = i64[count]
shape_mitm_pairs = i64[count]
shape_mitm_ms = i64[count]
shape_mitm_failures = i64[count]

# A failed segment's computation is still operational work and must remain in
# the parent counters. A later healthy segment exercises ordinary accumulation.
failed_moves = ffrpo_commit_operational(shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, 0, 100, 200, 3, 3000, 40, 1, 1) ## i64
healthy_moves = ffrpo_commit_operational(shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, 1, 10, 350, 1, 500, 7, 0, 0) ## i64
shape_moves[0] += failed_moves
shape_moves[1] += healthy_moves

failures_count += rect_parent_telemetry_expect("failed segment CPU work is retained", shape_cpu_moves[0] == 100)
failures_count += rect_parent_telemetry_expect("failed segment GPU work is retained", shape_gpu_moves[0] == 200)
failures_count += rect_parent_telemetry_expect("failed segment MITM work is retained", shape_mitm_attempts[0] == 3 && shape_mitm_pairs[0] == 3000 && shape_mitm_ms[0] == 40)
failures_count += rect_parent_telemetry_expect("failed segment MITM failure is retained", shape_mitm_failures[0] == 1)

ready = i64[count]
cpu_allocation = i64[count]
gpu_allocation = i64[count]
ranks = i64[count]
bits = i64[count]
rank_drops = i64[count]
density_gains = i64[count]
exposure = i64[count]
child_failures = i64[count]
gpu_failures = i64[count]
scores = i64[count]
side_loaded = i64[count]
side_seeded = i64[count]
side_saved = i64[count]
side_rejects = i64[count]
side_write_failures = i64[count]
i = 0 ## i64
while i < count
  ready[i] = 1
  ranks[i] = 47 + i * 13
  bits[i] = 438 + i * 190
  i += 1
child_failures[0] = 1

body = ffrpo_status_body("running", 7, 3, 11, 4, 8192, failed_moves + healthy_moves, 1, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, shape_moves, shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, exposure, child_failures, gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
lines = body.split("\n")
header = lines[0]
shape0 = lines[1]
shape1 = lines[2]

failures_count += rect_parent_telemetry_expect("header preserves combined total", header.include?("total_moves=660"))
failures_count += rect_parent_telemetry_expect("header totals CPU and GPU independently", header.include?("total_cpu_moves=110") && header.include?("total_gpu_moves=550"))
failures_count += rect_parent_telemetry_expect("header totals MITM accounting", header.include?("total_mitm_attempts=4") && header.include?("total_mitm_pairs=3500") && header.include?("total_mitm_ms=47") && header.include?("total_mitm_failures=1"))
failures_count += rect_parent_telemetry_expect("first shape exposes failed work", shape0.include?("moves=300 cpu_moves=100 gpu_moves=200 mitm_attempts=3 mitm_pairs=3000 mitm_ms=40 mitm_failures=1"))
failures_count += rect_parent_telemetry_expect("second shape exposes healthy work", shape1.include?("moves=360 cpu_moves=10 gpu_moves=350 mitm_attempts=1 mitm_pairs=500 mitm_ms=7 mitm_failures=0"))
failures_count += rect_parent_telemetry_expect("status remains degraded by the failed segment", header.include?("health=degraded") && shape0.include?("failures=2"))

if failures_count != 0
  << "FAIL rectangular parent telemetry failures=" + failures_count.to_s()
  exit(1)

<< "PASS rectangular parent telemetry totals and failed-work retention"
