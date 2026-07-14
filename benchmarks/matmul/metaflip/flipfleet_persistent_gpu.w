# File-mailbox ABI for persistent generic/rectangular cal2zone workers.
#
# A worker owns its Metal device, library, pipeline, queue, and buffers across
# commands. The coordinator atomically publishes one bounded dispatch command;
# the worker atomically acknowledges only after its candidate output is fully
# written. The coordinator clears both mailboxes before launch; generation
# numbers then reject delayed or duplicate contents within that session.

-> ffpg_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffpg_command(generation, action, steps, reseed, margin, workq, wanderq, wthr, escapes) (i64 i64 i64 i64 i64 i64 i64 i64 i64)
  generation.to_s() + " " + action.to_s() + " " + steps.to_s() + " " + reseed.to_s() + " " + margin.to_s() + " " + workq.to_s() + " " + wanderq.to_s() + " " + wthr.to_s() + " " + escapes.to_s() + "\n"

-> ffpg_publish(path, body, tag) (String String String) i64
  tmp = path + ".tmp." + tag
  wrote = write_file(tmp, body)
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      return 1
  0

-> ffpg_prepare_mailboxes(command_path, ack_path, tag) (String String String) i64
  if ffpg_publish(command_path, "", tag + ".command") != 1
    return 0
  if ffpg_publish(ack_path, "", tag + ".ack") != 1
    return 0
  1

-> ffpg_launch_command(epoch_command, command_path, ack_path) (String String String)
  epoch_command + " " + ffpg_shell_quote(command_path) + " " + ffpg_shell_quote(ack_path)

-> ffpg_ack_matches(text, generation, state) (String i64 String) i64
  if text == nil
    return 0
  lines = text.split("\n")
  if lines.size() < 1
    return 0
  parts = lines[0].split(" ")
  if parts.size() < 2
    return 0
  if parts[0].to_i() != generation
    return 0
  if parts[1] != state
    return 0
  1

-> ffpg_wait_ack(path, generation, state, timeout_ms) (String i64 String i64) i64
  start = ccall("__w_clock_ms") ## i64
  while ccall("__w_clock_ms") - start < timeout_ms
    if ffpg_ack_matches(read_file(path), generation, state) == 1
      return 1
    z = ccall("__w_sleep_ms", 10)
  0
