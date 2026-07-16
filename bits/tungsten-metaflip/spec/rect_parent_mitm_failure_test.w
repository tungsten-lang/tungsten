use ../lib/metaflip/rect/portfolio

failures_count = 0 ## i64

-> rect_parent_mitm_expect(label, condition) (String bool) i64
  if condition
    << "PASS " + label
    return 0
  << "FAIL " + label
  1

# Exercise the exact child-to-parent boundary with the terminal fields emitted
# by a real failed MITM launch: cal2zone itself remains healthy, while the
# independent surgery lane degrades health and contributes one failure.
child_status = "schema=1 mode=rect producer_state=stopped gpu_failures=0 gpu_degraded=1 mitm_attempts=1 mitm_pairs=1176576 mitm_ms=130 mitm_failures=1"
acc_mitm_failures = i64[1]
acc_child_degraded = i64[1]
parsed = ffrpo_accumulate_accelerator_status(child_status, 0, acc_mitm_failures, acc_child_degraded) ## i64
failures_count += rect_parent_mitm_expect("failed MITM crosses child-parent boundary", parsed == 1 && acc_mitm_failures[0] == 1 && acc_child_degraded[0] == 1)
failed_health = ffrpo_accelerator_degraded_after_epoch(0, 1, 0, acc_child_degraded[0]) ## i64
failures_count += rect_parent_mitm_expect("failing epoch degrades accelerator health", failed_health == 1)

labels = ["2x5x6"]
shape_moves = i64[1]
shape_cpu_moves = i64[1]
shape_gpu_moves = i64[1]
shape_mitm_attempts = i64[1]
shape_mitm_pairs = i64[1]
shape_mitm_ms = i64[1]
shape_mitm_failures = i64[1]
committed = ffrpo_commit_operational(shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, 0, 1000, 3200, 1, 1176576, 130, acc_mitm_failures[0], 0) ## i64
shape_moves[0] = committed

ready = i64[1]
cpu_allocation = i64[1]
gpu_allocation = i64[1]
ranks = i64[1]
bits = i64[1]
rank_drops = i64[1]
density_gains = i64[1]
exposure = i64[1]
child_failures = i64[1]
gpu_failures = i64[1]
scores = i64[1]
side_loaded = i64[1]
side_seeded = i64[1]
side_saved = i64[1]
side_rejects = i64[1]
side_write_failures = i64[1]
ready[0] = 1
ranks[0] = 47
bits[0] = 438

parent_status = ffrpo_status_body("stopped", 3, 1, 1, 1, 32, committed, acc_child_degraded[0], labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, shape_moves, shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, exposure, child_failures, gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
lines = parent_status.split("\n")
header = lines[0]
shape = lines[1]
failures_count += rect_parent_mitm_expect("parent health degrades without blaming cal2zone", header.include?("health=degraded") && header.include?("total_mitm_failures=1") && shape.include?("failures=1") && shape.include?("gpu_failures=0") && shape.include?("mitm_failures=1"))

# A successful no-hit launch is ordinary search exhaustion, not a failure.
no_hit_status = "schema=1 mode=rect producer_state=stopped gpu_failures=0 gpu_degraded=0 mitm_attempts=1 mitm_pairs=1176576 mitm_ms=120 mitm_failures=0"
no_hit_failures = i64[1]
no_hit_degraded = i64[1]
parsed = ffrpo_accumulate_accelerator_status(no_hit_status, 0, no_hit_failures, no_hit_degraded)
failures_count += rect_parent_mitm_expect("successful MITM no-output remains healthy", parsed == 0 && no_hit_failures[0] == 0 && no_hit_degraded[0] == 0)
recovered_health = ffrpo_accelerator_degraded_after_epoch(failed_health, 1, 0, no_hit_degraded[0]) ## i64
unobserved_health = ffrpo_accelerator_degraded_after_epoch(failed_health, 0, 0, 0) ## i64
failures_count += rect_parent_mitm_expect("health recovers only after a clean accelerator epoch", recovered_health == 0 && unobserved_health == 1 && shape_mitm_failures[0] == 1)

if failures_count != 0
  << "FAIL rectangular parent MITM failure propagation failures=" + failures_count.to_s()
  exit(1)

<< "PASS rectangular parent MITM failure propagation"
