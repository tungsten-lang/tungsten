use flipfleet_rect_portfolio

-> ffrpot_expect(label, condition) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

failures = 0 ## i64
labels = []
codes = i64[32]
count = ffrpo_parse_shapes(ffrpo_default_shape_spec(), labels, codes) ## i64
failures += ffrpot_expect("default shape parse", count == 9 && labels[0] == "2x2x5" && codes[4] == 446 && codes[6] == 256 && codes[8] == 356)
failures += ffrpot_expect("new CPU profiles parse", ffrpo_parse_shapes("4x6x7,5x6x7", [], i64[4]) == 2)
failures += ffrpot_expect("next CPU profiles parse", ffrpo_parse_shapes("3x4x7,3x5x6,3x5x7,4x5x8,4x6x6,4x6x8", [], i64[8]) == 6)
failures += ffrpot_expect("tiny CPU profiles parse", ffrpo_parse_shapes("2x3x4,2x4x5", [], i64[2]) == 2)
failures += ffrpot_expect("235 live profile parses", ffrpo_parse_shapes("2x3x5", [], i64[1]) == 1)
failures += ffrpot_expect("256 high-leverage profile parses", ffrpo_parse_shapes("2x5x6", [], i64[1]) == 1)
failures += ffrpot_expect("inner-two gap profiles parse", ffrpo_parse_shapes("2x2x5,2x2x6", [], i64[2]) == 2)
failures += ffrpot_expect("duplicate rejected", ffrpo_parse_shapes("4x5x7,4x5x7", [], i64[4]) == 0)
failures += ffrpot_expect("unsupported rejected", ffrpo_parse_shapes("9x9x9", [], i64[4]) == 0)

body = "schema=1 cpu_moves=123 gpu_failures=2\n"
failures += ffrpot_expect("status integer", ffrpo_status_i64(body, "cpu_moves", 0) == 123 && ffrpo_status_i64(body, "missing", 7) == 7)
failures += ffrpot_expect("backoff bounded", ffrpo_backoff(1) == 2 && ffrpo_backoff(9) == 16)
# Straggler-fill helpers: predict slowest base quota finish; fill while one
# average round wall-time still fits before that deadline.
failures += ffrpot_expect("base finish from measured wall", ffrpo_predict_base_finish_ms(1000, 5000, 4, 4, 1, 800) == 1800)
failures += ffrpot_expect("base finish from live rate", ffrpo_predict_base_finish_ms(1000, 3000, 4, 2, 0, 0) == 5000)
failures += ffrpot_expect("base finish unknown before first round", ffrpo_predict_base_finish_ms(1000, 1500, 4, 0, 0, 0) == 0)
failures += ffrpot_expect("fill when avg fits remaining", ffrpo_should_fill_round(100, 1000, 1500) == 1)
failures += ffrpot_expect("no fill when avg exceeds remaining", ffrpo_should_fill_round(100, 1000, 1050) == 0)
failures += ffrpot_expect("no fill at or past deadline", ffrpo_should_fill_round(50, 2000, 2000) == 0)
failures += ffrpot_expect("no fill with zero avg", ffrpo_should_fill_round(0, 1000, 2000) == 0)
path_root = "/tmp/flipfleet_rect_portfolio_state"
failures += ffrpot_expect("explicit best path isolation", ffrpo_best_path("/tmp/best", 1, "4x5x7", path_root) == "/tmp/best.4x5x7")
failures += ffrpot_expect("default best uses live root", ffrpo_best_path("ignored", 0, "4x5x7", path_root) == path_root + "/checkpoints/gf2/4x5x7/best.txt")
failures += ffrpot_expect("explicit child status isolation", ffrpo_child_status_path("/tmp/status", 1, "4x5x7", path_root, "run-1") == "/tmp/status.4x5x7")
failures += ffrpot_expect("default child status uses live root", ffrpo_child_status_path("ignored", 0, "4x5x7", path_root, "run-1") == path_root + "/runs/gf2/4x5x7/run-1/status.txt")

tiny_metrics = i64[2]
metrics_nonce = ccall("__w_clock_ms").to_s()
closure_missing_best = "/tmp/flipfleet_rect_portfolio_missing_234_" + metrics_nonce
failures += ffrpot_expect("closure profile exact seed metrics", ffrpo_load_metrics("2x3x4", ".", closure_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 20 && tiny_metrics[1] == 130)
failures += ffrpot_expect("235 exact seed metrics", ffrpo_load_metrics("2x3x5", ".", closure_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 25 && tiny_metrics[1] == 170)
tiny_missing_best = "/tmp/flipfleet_rect_portfolio_missing_245_" + metrics_nonce
failures += ffrpot_expect("tiny profile exact seed metrics", ffrpo_load_metrics("2x4x5", ".", tiny_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 33 && tiny_metrics[1] == 241)
gap_missing_best = "/tmp/flipfleet_rect_portfolio_missing_225_" + metrics_nonce
failures += ffrpot_expect("225 exact seed metrics", ffrpo_load_metrics("2x2x5", ".", gap_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 18 && tiny_metrics[1] == 84)
failures += ffrpot_expect("226 exact seed metrics", ffrpo_load_metrics("2x2x6", ".", gap_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 21 && tiny_metrics[1] == 108)
cross_missing_best = "/tmp/flipfleet_rect_portfolio_missing_256_" + metrics_nonce
failures += ffrpot_expect("256 exact seed metrics", ffrpo_load_metrics("2x5x6", ".", cross_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 47 && tiny_metrics[1] == 438)
next_missing_best = "/tmp/flipfleet_rect_portfolio_missing_next_" + metrics_nonce
failures += ffrpot_expect("347 exact seed metrics", ffrpo_load_metrics("3x4x7", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 64 && tiny_metrics[1] == 519)
failures += ffrpot_expect("356 exact seed metrics", ffrpo_load_metrics("3x5x6", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 68 && tiny_metrics[1] == 634)
failures += ffrpot_expect("357 exact seed metrics", ffrpo_load_metrics("3x5x7", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 79 && tiny_metrics[1] == 699)
failures += ffrpot_expect("458 exact seed metrics", ffrpo_load_metrics("4x5x8", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 118 && tiny_metrics[1] == 1283)
failures += ffrpot_expect("466 exact seed metrics", ffrpo_load_metrics("4x6x6", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 105 && tiny_metrics[1] == 1197)
failures += ffrpot_expect("468 exact seed metrics", ffrpo_load_metrics("4x6x8", ".", next_missing_best, 0, tiny_metrics, 0) == 1 && tiny_metrics[0] == 140 && tiny_metrics[1] == 1560)

gpu_host_ready = i64[3]
gpu_host_allocation = i64[3]
gpu_host_scores = i64[3]
gpu_host_ready[2] = 1
gpu_host_allocation[0] = 1
gpu_host_scores[0] = 100
gpu_host_scores[2] = 200
host_moved = ffrpo_ensure_gpu_host(0, gpu_host_ready, gpu_host_allocation, gpu_host_scores) ## i64
failures += ffrpot_expect("small-J GPU host", host_moved == 1 && gpu_host_allocation[0] == 0 && gpu_host_allocation[2] == 1 && ffrpp_sum(gpu_host_allocation, 3) == 1)

# End-to-end bounded coordinator smoke: one exact shape, one worker, one
# portfolio epoch, no Metal.  The parent and child status/checkpoint names are
# isolated by a clock nonce so the test never adopts a stale run.
nonce = ccall("__w_clock_ms").to_s()
best_base = "/tmp/flipfleet_rect_portfolio_test_best_" + nonce
status_path = "/tmp/flipfleet_rect_portfolio_test_status_" + nonce
result = ffrpo_run("3x3x4", ".", "/tmp/flipfleet_rect_portfolio_state_" + nonce, best_base, 1, status_path, 1, "portfolio_test_" + nonce, 1, 200, 1, 0, 1, 4, 4, 0, 0, "adaptive", 10, 1, "", 0, 1, 0, 0, 0) ## i64
failures += ffrpot_expect("bounded coordinator returns", result == 0)
portfolio_status = read_file(status_path)
child_status = read_file(status_path + ".3x3x4")
failures += ffrpot_expect("portfolio status schema", portfolio_status != nil && portfolio_status.include?("mode=rect-portfolio") && portfolio_status.include?("shape=3x3x4"))
failures += ffrpot_expect("child status exact", child_status != nil && child_status.include?("mode=rect") && child_status.include?("best_rank=29") && child_status.include?("exact_rejects=0"))
metrics = i64[2]
failures += ffrpot_expect("portfolio checkpoint exact", ffrpo_load_metrics("3x3x4", ".", best_base + ".3x3x4", 0, metrics, 0) == 1 && metrics[0] == 29)

# A global naive reset must persist every selected shape even when J is too
# small to launch them all in that epoch. At epoch zero/J=1, 3x4x4 is outside
# the rotating CPU window, so its rank-48 checkpoint proves the coordinator
# reset it rather than leaving a missing or catalog-rank file behind.
reset_nonce = ccall("__w_clock_ms").to_s()
reset_best = "/tmp/flipfleet_rect_portfolio_reset_best_" + reset_nonce
reset_status = "/tmp/flipfleet_rect_portfolio_reset_status_" + reset_nonce
reset_result = ffrpo_run("3x3x4,3x4x4", ".", "/tmp/flipfleet_rect_portfolio_reset_state_" + reset_nonce, reset_best, 1, reset_status, 1, "portfolio_reset_" + reset_nonce, 1, 1, 1, 0, 1, 4, 4, 0, 0, "adaptive", 1, 1, "", 0, 1, 0, 0, 1) ## i64
failures += ffrpot_expect("bounded all-shape reset returns", reset_result == 0)
reset_metrics = i64[2]
failures += ffrpot_expect("inactive shape checkpoint reset", ffrpo_load_metrics("3x4x4", ".", reset_best + ".3x4x4", 0, reset_metrics, 0) == 1 && reset_metrics[0] == 48)

if failures == 0
  << "PASS flipfleet rectangular portfolio helpers"
  exit(0)
<< "FAIL flipfleet rectangular portfolio helpers failures=" + failures.to_s()
exit(1)
