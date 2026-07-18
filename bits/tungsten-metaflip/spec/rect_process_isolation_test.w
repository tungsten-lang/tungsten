use ../lib/metaflip/rect/portfolio

failures = 0 ## i64

-> rect_process_expect(label, condition) (String bool) i64
  if condition
    << "PASS " + label
    return 0
  << "FAIL " + label
  1

command = ffrpo_child_command("/tmp/meta flip", "2x2x5", "/tmp/runtime root", "/tmp/best file", "/tmp/status file", "child_7", 3, 101, 2, 17, 5, 6, 0, 32, 303, 4, "", 0, 1, 1, 1234567, 9)
failures += rect_process_expect("child re-execs the coordinator", command.starts_with?("'/tmp/meta flip' --tensor '2x2x5'"))
failures += rect_process_expect("child receives exact private restart schedule", command.include?("--rect-portfolio-child") && command.include?("--rect-restart-nonce 1234567") && command.include?("--rect-door-ticket 9"))
failures += rect_process_expect("child receives bounded campaign dimensions", command.include?("-J 3") && command.include?("--steps 101") && command.include?("--rounds 2") && command.include?("--secs 17"))
failures += rect_process_expect("child preserves CPU-only and naive controls", command.include?("--no-gpu") && command.include?("--naive") && command.include?("--stop-on-record"))
failures += rect_process_expect("child output cannot corrupt parent TUI", command.ends_with?(" > '/tmp/status file.child.log' 2>&1"))

quoted_command = ffrpo_child_command("/tmp/meta'flip", "2x2x5", "/tmp/runtime", "/tmp/best", "/tmp/status", "child_quote", 1, 1, 1, 0, 4, 4, 0, 32, 1, 1, "", 0, 0, 0, 1, 0)
failures += rect_process_expect("child shell quoting preserves apostrophes", quoted_command.starts_with?("'/tmp/meta'\"'\"'flip' --tensor"))

exit_codes = i64[1]
elapsed_ms = i64[1]
thread = ffrpo_spawn_shape("/usr/bin/true", "2x2x5", "/tmp/runtime", "/tmp/best", "/tmp/metaflip_rect_process_true_status", "child_true", 1, 1, 1, 0, 4, 4, 0, 32, 1, 1, "", 0, 0, 0, 1, 0, exit_codes, elapsed_ms, 0)
joined = ffrc_thread_join_release(thread)
failures += rect_process_expect("process-backed child is joined successfully", joined == true && exit_codes[0] == 0 && elapsed_ms[0] >= 0)

launcher_commands = [""]
launcher_states = i64[1]
launcher_exit_codes = i64[1]
launcher_elapsed_ms = i64[1]
launcher_threads = []
launcher = ffrpo_start_process_launcher(launcher_commands, launcher_states, launcher_exit_codes, launcher_elapsed_ms, 0)
launcher_threads.push(launcher)
dispatched = ffrpo_dispatch_shape("/usr/bin/true", launcher_threads, launcher_commands, launcher_states, "2x2x5", "/tmp/runtime", "/tmp/best", "/tmp/metaflip_rect_launcher_true_status", "launcher_true", 1, 1, 1, 0, 4, 4, 0, 32, 1, 1, "", 0, 0, 0, 1, 0, launcher_exit_codes, launcher_elapsed_ms, 0)
polls = 0 ## i64
while launcher_states[0] == 1 && polls < 1000
  ccall("__w_sleep_ms", 1)
  polls += 1
finished = ffrpo_finish_segment("/usr/bin/true", dispatched, launcher_states, 0) ## i64
stopped = ffrpo_stop_process_launchers("/usr/bin/true", launcher_threads, launcher_states) ## i64
failures += rect_process_expect("persistent launcher dispatches and returns idle", dispatched == launcher && finished == 1 && launcher_exit_codes[0] == 0 && launcher_states[0] == 0 - 1 && stopped == 1)

if failures != 0
  << "FAIL rectangular process isolation failures=" + failures.to_s()
  exit(1)

<< "PASS rectangular process isolation"
