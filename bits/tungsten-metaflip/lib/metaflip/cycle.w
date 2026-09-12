# Sequential campaigns reuse the current foreground process and terminal.
# After exact shutdown, exec replaces the arena rather than accumulating one
# campaign's native arrays per visit. There is no extra CPU/GPU supervisor.
use cli
use seeds/rect
use composition/utility

-> ffcy_optimal_rank(label) (String) i64
  n = ffcli_parse_square_tensor(label) ## i64
  if n > 0
    return ffpr_exact_rank(n,n,n)
  ffpr_exact_rank(ffrp_n(label),ffrp_m(label),ffrp_p(label))

# Default parent exploration: 15s, then 7s/3s on completed unproductive
# visits. A verified downstream rank decrease earns up to 30s next time.
# A user-specified shorter cycle ceiling always wins; no shape is starved.
-> ffcy_parent_seconds(ceiling, misses, reward) (i64 i64 i64) i64
  seconds = 15 ## i64
  if reward > 0
    seconds = 30
  else
    if misses > 0
      seconds = 7
    if misses > 1
      seconds = 3
  if seconds > ceiling
    seconds = ceiling
  seconds

# A partial/interrupted visit and a malformed queue are never a failed trial.
-> ffcy_parent_complete(root, visits) (String i64) i64
  ffrf_atomic(root + "/composition/utility/completed", visits.to_s() + "\n", "cycle")

-> ffcy_parent_pending(root) (String) i64
  queues = ["", "/composition", "/composition/mixed", "/composition/transforms", "/composition/feedback"]
  pending = 0 ## i64
  i = 0 ## i64
  while i < queues.size()
    submitted = ffmd_count(root + queues[i] + "/submitted") ## i64
    consumed = ffmd_count(root + queues[i] + "/consumed") ## i64
    if submitted < 0 || consumed < 0 || consumed > submitted
      return 0-1
    pending += submitted-consumed
    i += 1
  parents = ffmd_count(root + "/composition/mixed/parent-submitted") ## i64
  cursor = ffmd_count(root + "/composition/mixed/context") ## i64
  if parents < 0 || parents > 1000000000000 || cursor < 0 || cursor > 27*parents
    return 0-1
  pending+27*parents-cursor

# meta = saved, misses, visit count, pending, telemetry error. Scheduling is
# advisory only. Malformed or rolled-back state resets to exploration.
-> ffcy_parent_budget(root, ceiling, meta) (String i64 i64[]) i64
  meta[4] = 0
  queue = root + "/composition/utility/"
  saved = ffmd_count(queue + "saved") ## i64
  old_saved = saved ## i64
  misses = 0 ## i64
  visits = 0 ## i64
  raw = File.read_prefix(queue + "cycle", 128)
  if saved < 0 || saved > 1000000000000
    saved = 0
    old_saved = 0
    meta[4] = 1
  if raw != nil
    fields = raw.strip().split(" ")
    if fields.size() == 4 && fields[0] == "MFCP1"
      old_saved = ffw_parse_decimal_i64(fields[1])
      misses = ffw_parse_decimal_i64(fields[2])
      visits = ffw_parse_decimal_i64(fields[3])
      canonical = "MFCP1 " + old_saved.to_s() + " " + misses.to_s() + " " + visits.to_s() + "\n"
      if old_saved < 0 || old_saved > saved || misses < 0 || misses > 2 || visits < 0 || visits > 1000000000000 || raw != canonical
        meta[4] = 1
    else
      meta[4] = 1
  if meta[4] != 0
    old_saved = saved
    misses = 0
    visits = 0
  pending = ffcy_parent_pending(root) ## i64
  reward = saved - old_saved ## i64
  if reward > 0
    misses = 0
  elsif visits > 0 && ffmd_count(queue + "completed") == visits && pending == 0 && misses < 2
    misses += 1
  meta[0] = saved
  meta[1] = misses
  meta[2] = visits + 1
  meta[3] = pending
  next_record = "MFCP1 " + saved.to_s() + " " + misses.to_s() + " " + (visits+1).to_s() + "\n"
  if !File.mkdir_p(queue)
    meta[4] = 1
  elsif ffrf_atomic(queue + "cycle", next_record, "cycle") != 1
    meta[4] = 1
  ffcy_parent_seconds(ceiling, misses, reward)

-> ffcy_default_shapes()
  labels = ["2x2", "3x3", "4x4", "5x5", "6x6", "7x7"]
  square = 8 ## i64
  while square <= 16
    labels.push(square.to_s() + "x" + square.to_s())
    square += 1
  n = 2 ## i64
  while n <= 7
    m = n ## i64
    while m <= 9
      p = m ## i64
      while p <= 9
        if ffrp_supported(n, m, p) == 1
          labels.push(ffrp_label(n, m, p))
        p += 1
      m += 1
    n += 1
  labels

-> ffcy_parse_shapes(spec, labels) i64
  if spec == "" || spec.starts_with?(",") || spec.ends_with?(",") || spec.include?(",,")
    return 0
  parts = spec.split(",")
  i = 0 ## i64
  while i < parts.size()
    label = parts[i].strip().downcase
    n = ffcli_parse_square_tensor(label) ## i64
    if n >= 2 && n <= 16
      label = n.to_s() + "x" + n.to_s()
    elsif ffrp_supported_label(label) == 0
      return 0
    if labels.include?(label)
      return 0
    labels.push(label)
    i += 1
  labels.size()

-> ffcy_slice_seconds(seconds, deadline_ms, now_ms) (i64 i64 i64) i64
  if deadline_ms == 0
    return seconds
  if now_ms >= deadline_ms
    return 0
  remaining_ms = deadline_ms - now_ms ## i64
  if remaining_ms >= seconds * 1000
    return seconds
  (remaining_ms + 999) / 1000

# Keep public arguments byte-for-byte, replacing only our two private cursor
# fields. In particular --secs is the whole run limit, not a fresh per-visit
# limit; the absolute deadline below prevents it from restarting at every exec.
-> ffcy_next_argv(binary, arguments, position, deadline_ms, value_options)
  result = [binary]
  i = 0 ## i64
  while i < arguments.size()
    arg = arguments[i]
    if arg == "--cycle-position" || arg == "--cycle-deadline-ms"
      i += 2
    else
      result.push(arg)
      i += 1
      if value_options.include?(arg)
        result.push(arguments[i])
        i += 1
  result.push("--cycle-position")
  result.push(position.to_s())
  result.push("--cycle-deadline-ms")
  result.push(deadline_ms.to_s())
  result

# Copy all strings into owned NUL-terminated storage: w_string_byte_ptr can
# refer to a short-string scratch ring, so keeping its pointers is unsafe.
# execv preserves PID, foreground process group and terminal ownership. It is
# called only after all CPU/GPU/refinement workers and writes have drained.
-> ffcy_exec(arguments) i64
  if arguments.size() < 1
    return 2
  lengths = i64[arguments.size()]
  size = 0 ## i64
  i = 0 ## i64
  while i < arguments.size()
    lengths[i] = ccall_nobox("w_string_byte_length", arguments[i])
    size += lengths[i] + 1
    i += 1
  bytes = u8[size]
  pointers = i64[arguments.size() + 1]
  storage = ccall_nobox("w_array_data_ptr", bytes) ## i64
  cursor = 0 ## i64
  i = 0
  while i < arguments.size()
    pointers[i] = storage + cursor
    source = ccall_nobox("w_string_byte_ptr", arguments[i]) ## i64
    j = 0 ## i64
    while j < lengths[i]
      bytes[cursor] = raw_load_u8(source, j)
      cursor += 1
      j += 1
    bytes[cursor] = 0
    cursor += 1
    i += 1
  pointers[arguments.size()] = 0
  argv_ptr = ccall_nobox("w_array_data_ptr", pointers) ## i64
  failed = ccall_nobox("execv", pointers[0], argv_ptr) ## i64
  << "metaflip: could not start the next cycle visit (execv=" + failed.to_s() + ")"
  2

-> ffcy_continue(binary, arguments, position, deadline_ms, value_options) i64
  if ccall("__w_interrupted") != 0
    return 0
  if deadline_ms > 0 && ccall("__w_clock_ms") >= deadline_ms
    return 0
  if position >= 9223372036854775806
    return 0
  flush()
  ffcy_exec(ffcy_next_argv(binary, arguments, position + 1, deadline_ms, value_options))
