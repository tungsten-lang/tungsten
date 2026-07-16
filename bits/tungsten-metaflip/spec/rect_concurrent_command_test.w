use ../lib/metaflip/rect/campaign

failures = 0 ## i64

-> rect_concurrent_expect(label, condition) (String bool) i64
  if condition
    << "PASS " + label
    return 0
  << "FAIL " + label
  1

tag = ccall("__w_clock_ms").to_s()
log_a = "/tmp/metaflip_rect_concurrent_a_" + tag + ".log"
log_b = "/tmp/metaflip_rect_concurrent_b_" + tag + ".log"
log_fail = "/tmp/metaflip_rect_concurrent_fail_" + tag + ".log"
elapsed_a = i64[1]
elapsed_b = i64[1]
elapsed_fail = i64[1]

failures += rect_concurrent_expect("standalone MITM cadence is unchanged", ffrmw_due(0, 0) == 1 && ffrmw_due(1, 0) == 0 && ffrmw_due(8, 0) == 1)
failures += rect_concurrent_expect("portfolio child runs one MITM launch", ffrmw_due(0, 1) == 1 && ffrmw_due(1, 1) == 0)
failures += rect_concurrent_expect("2x5x6 retains the 384-factor pool", ffrmw_pool(2, 5, 6) == 384)

# Each bounded child sleeps long enough that overlap is visible well above the
# millisecond clock resolution.  Compare aggregate child occupancy to parent
# wall time instead of imposing a machine-specific absolute deadline.
t0 = ccall("__w_clock_ms") ## i64
thread_a = ffrc_spawn_logged_command("sleep 0.20; printf child-a", log_a, elapsed_a)
thread_b = ffrc_spawn_logged_command("sleep 0.20; printf child-b", log_b, elapsed_b)
ok_a = ffrc_thread_join_bounded(thread_a, 2000) ## i64
ok_b = ffrc_thread_join_bounded(thread_b, 2000) ## i64
wall_ms = ccall("__w_clock_ms") - t0 ## i64

failures += rect_concurrent_expect("both logged children succeed", ok_a == 1 && ok_b == 1)
failures += rect_concurrent_expect("first child log is captured", read_file(log_a) == "child-a")
failures += rect_concurrent_expect("second child log is captured", read_file(log_b) == "child-b")
failures += rect_concurrent_expect("child wall metrics are populated", elapsed_a[0] >= 150 && elapsed_b[0] >= 150)
failures += rect_concurrent_expect("children overlap", wall_ms + 80 < elapsed_a[0] + elapsed_b[0])

failed_thread = ffrc_spawn_logged_command("false", log_fail, elapsed_fail)
failed_ok = ffrc_thread_join_bounded(failed_thread, 2000) ## i64
failures += rect_concurrent_expect("failed child propagates false", failed_ok == 0)
failures += rect_concurrent_expect("failed child still records wall time", elapsed_fail[0] >= 0)

timeout_log = "/tmp/metaflip_rect_concurrent_timeout_" + tag + ".log"
timeout_elapsed = i64[1]
timeout_thread = ffrc_spawn_logged_command("sleep 5", timeout_log, timeout_elapsed)
timeout_t0 = ccall("__w_clock_ms") ## i64
timeout_ok = ffrc_thread_join_bounded(timeout_thread, 50) ## i64
timeout_wall = ccall("__w_clock_ms") - timeout_t0 ## i64
failures += rect_concurrent_expect("timed child is cancelled", timeout_ok == 0)
failures += rect_concurrent_expect("timeout kills and reaps promptly", timeout_wall < 1000)

if failures != 0
  << "FAIL rectangular concurrent command lifecycle failures=" + failures.to_s()
  exit(1)

<< "PASS rectangular concurrent command lifecycle wall_ms=" + wall_ms.to_s() + " child_ms=" + elapsed_a[0].to_s() + "/" + elapsed_b[0].to_s()
