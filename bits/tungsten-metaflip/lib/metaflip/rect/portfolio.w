# Adaptive multi-shape rectangular Metaflip coordinator.
#
# One portfolio epoch runs the selected single-shape coordinators concurrently
# with disjoint CPU/GPU budgets. Each child owns an independent exact
# checkpoint, sticky-island population, GPU relay, and status files for the
# duration of the epoch. Reallocation happens only after every child reaches a
# clean round boundary. The next epoch is an intentional exact restart from
# that shape's checkpoint, refreshing basins without unsafe live migration.
#
# Within an epoch, every shape first runs `shape_epoch_rounds` ordinary rounds
# (default four). Fast shapes then keep taking one extra round at a time while
# their observed average round wall-time still fits before the predicted finish
# of the slowest shape's base quota — straggler-fill instead of sitting idle at
# the portfolio join.

use campaign
use policy
use tui
use ../paths

-> ffrpo_shape_code(label) (String) i64
  normalized = label.strip().downcase
  if ffrp_supported_label(normalized) == 0
    return 0
  ffrp_n(normalized) * 100 + ffrp_m(normalized) * 10 + ffrp_p(normalized)

-> ffrpo_parse_shapes(spec, labels, codes)
  parts = spec.split(",")
  if parts.size() < 1 || parts.size() > codes.size()
    return 0
  count = 0 ## i64
  i = 0 ## i64
  while i < parts.size()
    label = parts[i].strip().downcase
    code = ffrpo_shape_code(label) ## i64
    if code == 0
      return 0
    duplicate = 0 ## i64
    j = 0 ## i64
    while j < count
      if codes[j] == code
        duplicate = 1
      j += 1
    if duplicate != 0
      return 0
    labels.push(label)
    codes[count] = code
    count += 1
    i += 1
  count

-> ffrpo_default_shape_spec()
  "2x2x5,2x2x6,2x2x7,2x2x8,2x2x9,4x5x7,3x4x6,4x5x6,4x4x6,4x4x5,2x5x6,3x4x7,3x5x6"

-> ffrpo_status_i64(body, key, fallback) (String String i64) i64
  if body == nil
    return fallback
  prefix = key + "="
  fields = body.split(" ")
  i = 0 ## i64
  while i < fields.size()
    field = fields[i].strip()
    if field.starts_with?(prefix)
      return field.slice(prefix.size(), field.size() - prefix.size()).to_i()
    i += 1
  fallback

# Child status fields parsed by ffrpo_parse_child_status.  Keep this order
# stable: the portfolio reuses one fixed i64[19] scratch array for every child
# poll instead of allocating/splitting the same status body once per field.
#
#   0 sequence                 10 gpu_degraded
#   1 cpu_moves                11 exact_rejects
#   2 gpu_moves                12 side_archive_loaded
#   3 cpu_ms                   13 side_archive_seeded
#   4 gpu_ms                   14 side_archive_saved
#   5 mitm_attempts            15 side_archive_rejects
#   6 mitm_pairs               16 side_archive_write_failures
#   7 mitm_ms                  17 best_rank
#   8 mitm_failures            18 best_bits
#   9 gpu_failures

-> ffrpo_raw_key_equal(ptr, start, length, key) (i64 i64 i64 String) i64
  key_length = ccall_nobox("w_string_byte_length", key) ## i64
  if length != key_length
    return 0
  key_ptr = ccall_nobox("w_string_byte_ptr", key) ## i64
  i = 0 ## i64
  while i < length
    if raw_load_u8(ptr, start + i) != raw_load_u8(key_ptr, i)
      return 0
    i += 1
  1

# Map a raw key span to its fixed child-status slot.  Length and leading-byte
# dispatch leave at most two exact comparisons for any recognized key, while
# the exact comparison prevents a hash collision or prefix match from silently
# becoming telemetry.
-> ffrpo_child_status_key(ptr, start, length) (i64 i64 i64) i64
  if length < 1
    return 0 - 1
  first = raw_load_u8(ptr, start) ## i64
  if first == 98
    if length == 9
      if ffrpo_raw_key_equal(ptr, start, length, "best_rank") != 0
        return 17
      if ffrpo_raw_key_equal(ptr, start, length, "best_bits") != 0
        return 18
  if first == 99
    if length == 9 && ffrpo_raw_key_equal(ptr, start, length, "cpu_moves") != 0
      return 1
    if length == 6 && ffrpo_raw_key_equal(ptr, start, length, "cpu_ms") != 0
      return 3
  if first == 101
    if length == 13 && ffrpo_raw_key_equal(ptr, start, length, "exact_rejects") != 0
      return 11
  if first == 103
    if length == 9 && ffrpo_raw_key_equal(ptr, start, length, "gpu_moves") != 0
      return 2
    if length == 6 && ffrpo_raw_key_equal(ptr, start, length, "gpu_ms") != 0
      return 4
    if length == 12
      if ffrpo_raw_key_equal(ptr, start, length, "gpu_failures") != 0
        return 9
      if ffrpo_raw_key_equal(ptr, start, length, "gpu_degraded") != 0
        return 10
  if first == 109
    if length == 7 && ffrpo_raw_key_equal(ptr, start, length, "mitm_ms") != 0
      return 7
    if length == 10 && ffrpo_raw_key_equal(ptr, start, length, "mitm_pairs") != 0
      return 6
    if length == 13
      if ffrpo_raw_key_equal(ptr, start, length, "mitm_attempts") != 0
        return 5
      if ffrpo_raw_key_equal(ptr, start, length, "mitm_failures") != 0
        return 8
  if first == 115
    if length == 8 && ffrpo_raw_key_equal(ptr, start, length, "sequence") != 0
      return 0
    if length == 18 && ffrpo_raw_key_equal(ptr, start, length, "side_archive_saved") != 0
      return 14
    if length == 19
      if ffrpo_raw_key_equal(ptr, start, length, "side_archive_loaded") != 0
        return 12
      if ffrpo_raw_key_equal(ptr, start, length, "side_archive_seeded") != 0
        return 13
    if length == 20 && ffrpo_raw_key_equal(ptr, start, length, "side_archive_rejects") != 0
      return 15
    if length == 27 && ffrpo_raw_key_equal(ptr, start, length, "side_archive_write_failures") != 0
      return 16
  0 - 1

-> ffrpo_status_space(byte) (i64) i64
  if byte == 9 || byte == 10 || byte == 11 || byte == 12 || byte == 13 || byte == 32
    return 1
  0

# Decimal String#to_i-compatible parsing for status values: leading ASCII
# whitespace and an optional sign are accepted, digits stop at the first other
# byte, and a missing digit yields zero.
-> ffrpo_raw_status_i64(ptr, start, finish) (i64 i64 i64) i64
  cursor = start ## i64
  while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) != 0
    cursor += 1
  sign = 1 ## i64
  if cursor < finish && raw_load_u8(ptr, cursor) == 45
    sign = 0 - 1
    cursor += 1
  elsif cursor < finish && raw_load_u8(ptr, cursor) == 43
    cursor += 1
  value = 0 ## i64
  digits = 0 ## i64
  while cursor < finish
    byte = raw_load_u8(ptr, cursor) ## i64
    if byte < 48 || byte > 57
      break
    value = value * 10 + byte - 48
    digits += 1
    cursor += 1
  if digits == 0
    return 0
  value * sign

# Parse all coordinator-consumed child fields in one raw-byte pass.  The
# returned bit mask records presence independently from the parsed value, so a
# present malformed/zero field remains distinct from a missing field and each
# caller can retain its original fallback.  Like ffrpo_status_i64, the first
# matching token wins and literal ASCII space separates tokens; strip-style
# whitespace is removed only at token boundaries.
-> ffrpo_parse_child_status(body, values) (String i64[]) i64
  if values.size() < 19
    return 0
  i = 0 ## i64
  while i < 19
    values[i] = 0
    i += 1
  if body == nil
    return 0
  length = ccall_nobox("w_string_byte_length", body) ## i64
  ptr = ccall_nobox("w_string_byte_ptr", body) ## i64
  cursor = 0 ## i64
  seen = 0 ## i64
  while cursor < length
    token_start = cursor ## i64
    while cursor < length && raw_load_u8(ptr, cursor) != 32
      cursor += 1
    token_finish = cursor ## i64
    if cursor < length
      cursor += 1
    while token_start < token_finish && ffrpo_status_space(raw_load_u8(ptr, token_start)) != 0
      token_start += 1
    while token_finish > token_start && ffrpo_status_space(raw_load_u8(ptr, token_finish - 1)) != 0
      token_finish -= 1
    equal = token_start ## i64
    while equal < token_finish && raw_load_u8(ptr, equal) != 61
      equal += 1
    if equal < token_finish
      slot = ffrpo_child_status_key(ptr, token_start, equal - token_start) ## i64
      if slot >= 0
        flag = 1 << slot ## i64
        if (seen & flag) == 0
          values[slot] = ffrpo_raw_status_i64(ptr, equal + 1, token_finish)
          seen = seen | flag
  seen

# The final child record is the only status record whose best metrics may be
# used as the exact epoch handoff.  Keep this check allocation-free: these
# files are polled at 50 ms cadence on large hosts, so even one split/string
# per poll becomes visible parent RSS over a long campaign.
-> ffrpo_child_status_stopped(body) (String) i64
  if body == nil
    return 0
  length = ccall_nobox("w_string_byte_length", body) ## i64
  ptr = ccall_nobox("w_string_byte_ptr", body) ## i64
  cursor = 0 ## i64
  while cursor < length
    token_start = cursor ## i64
    while cursor < length && raw_load_u8(ptr, cursor) != 32
      cursor += 1
    token_finish = cursor ## i64
    if cursor < length
      cursor += 1
    while token_start < token_finish && ffrpo_status_space(raw_load_u8(ptr, token_start)) != 0
      token_start += 1
    while token_finish > token_start && ffrpo_status_space(raw_load_u8(ptr, token_finish - 1)) != 0
      token_finish -= 1
    if ffrpo_raw_key_equal(ptr, token_start, token_finish - token_start, "producer_state=stopped") != 0
      return 1
  0

# Child campaigns exact-gate every accepted candidate and exit successfully
# only after atomically replacing their checkpoint.  The terminal status can
# therefore carry rank/density between most portfolio epochs.  Reparse and
# independently verify every checkpoint at a fixed cadence (and whenever the
# terminal handoff is missing), keeping the optimization fail-closed without
# retaining thirteen split-heavy scheme parses per epoch.
-> ffrpo_metric_audit_due(epoch) (i64) i64
  if epoch < 1 || epoch % 64 == 0
    return 1
  0

-> ffrpo_parsed_status_i64(values, seen, slot, fallback) (i64[] i64 i64 i64) i64
  if slot < 0 || slot >= values.size() || (seen & (1 << slot)) == 0
    return fallback
  values[slot]

-> ffrpo_accumulate_parsed_accelerator_status(values, seen, slot, mitm_failures, child_degraded) (i64[] i64 i64 i64[] i64[]) i64
  if slot < 0 || slot >= mitm_failures.size() || slot >= child_degraded.size()
    return 0
  failures = ffrpo_parsed_status_i64(values, seen, 8, 0) ## i64
  if failures < 0
    failures = 0
  mitm_failures[slot] += failures
  if failures > 0 || ffrpo_parsed_status_i64(values, seen, 10, 0) > 0
    child_degraded[slot] = 1
  failures

# Accumulate the child accelerator-health fields that are intentionally kept
# separate from cal2zone failures. MITM failure must degrade parent health and
# remain visible in telemetry, but it must not feed the cal2zone backoff or
# disable an otherwise healthy GPU relay.
-> ffrpo_accumulate_accelerator_status(body, slot, mitm_failures, child_degraded) (String i64 i64[] i64[]) i64
  values = i64[19]
  seen = ffrpo_parse_child_status(body, values) ## i64
  ffrpo_accumulate_parsed_accelerator_status(values, seen, slot, mitm_failures, child_degraded)

# Health describes the latest observed accelerator epoch, while the separate
# failure counters remain cumulative. A shape that receives no accelerator
# work cannot prove recovery; the next clean GPU epoch can.
-> ffrpo_accelerator_degraded_after_epoch(previous, ran_gpu, gpu_failures, child_degraded) (i64 i64 i64 i64) i64
  if ran_gpu == 0
    return previous
  if gpu_failures > 0 || child_degraded != 0
    return 1
  0

# Predicted wall-clock ms when a shape will complete `min_rounds` island rounds.
# `rounds_done` is live status sequence while the base quota is still running;
# once base is complete, `base_wall_ms` is the measured wall time for that quota.
-> ffrpo_predict_base_finish_ms(epoch_start_ms, now_ms, min_rounds, rounds_done, base_complete, base_wall_ms) (i64 i64 i64 i64 i64 i64) i64
  if min_rounds < 1
    min_rounds = 1
  if base_complete != 0
    finish = epoch_start_ms + base_wall_ms ## i64
    if finish < epoch_start_ms
      return epoch_start_ms
    return finish
  if rounds_done < 1
    return 0
  wall = now_ms - epoch_start_ms ## i64
  if wall < 1
    wall = 1
  finish = epoch_start_ms + wall * min_rounds / rounds_done ## i64
  finish

# Start one more fill round when the shape's average round still fits before the
# predicted portfolio base deadline (slowest shape finishing its min rounds).
-> ffrpo_should_fill_round(avg_round_ms, now_ms, deadline_ms) (i64 i64 i64) i64
  if avg_round_ms < 1
    return 0
  remaining = deadline_ms - now_ms ## i64
  if remaining < 1
    return 0
  if avg_round_ms < remaining
    return 1
  0

-> ffrpo_backoff(failures) (i64) i64
  count = failures ## i64
  if count < 1
    return 1
  if count > 4
    count = 4
  delay = 1 ## i64
  i = 0 ## i64
  while i < count
    delay *= 2
    i += 1
  delay

-> ffrpo_best_path(base, explicit, tensor, state_dir) (String i64 String String)
  if explicit != 0
    return base + "." + tensor
  ffls_best_path(state_dir, "gf2", tensor)

-> ffrpo_child_status_path(parent, explicit, tensor, state_dir, run_tag) (String i64 String String String)
  if explicit != 0
    return parent + "." + tensor
  ffls_status_path(state_dir, "gf2", tensor, run_tag)

-> ffrpo_gpu_binary(base, tensor)
  if base == ""
    return ""
  base + "_" + tensor.replace("x", "")

-> ffrpo_raw_scheme_decimal(ptr, start, finish, output, slot) (i64 i64 i64 i64[] i64) i64
  if slot < 0 || slot >= output.size()
    return 0
  cursor = start ## i64
  sign = 1 ## i64
  if cursor < finish && raw_load_u8(ptr, cursor) == 45
    sign = 0 - 1
    cursor += 1
  elsif cursor < finish && raw_load_u8(ptr, cursor) == 43
    cursor += 1
  digits = 0 ## i64
  value = 0 ## i64
  while cursor < finish
    byte = raw_load_u8(ptr, cursor) ## i64
    if byte < 48 || byte > 57
      return 0
    value = value * 10 + byte - 48
    digits += 1
    cursor += 1
  if digits < 1
    return 0
  output[slot] = value * sign
  1

-> ffrpo_raw_scheme_r_prefix(ptr, start, finish) (i64 i64 i64) i64
  cursor = start ## i64
  while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) != 0
    cursor += 1
  token_start = cursor ## i64
  while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) == 0
    cursor += 1
  if cursor - token_start == 1 && raw_load_u8(ptr, token_start) == 82
    return 1
  0

# Parse one `u v w` or `R u v w` row without allocating token strings.
-> ffrpo_raw_scheme_row(ptr, start, finish, prefixed, output) (i64 i64 i64 i64 i64[]) i64
  cursor = start ## i64
  while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) != 0
    cursor += 1
  if prefixed != 0
    if cursor >= finish || raw_load_u8(ptr, cursor) != 82
      return 0
    cursor += 1
    if cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) == 0
      return 0
  field = 0 ## i64
  while field < 3
    while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) != 0
      cursor += 1
    token_start = cursor ## i64
    while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) == 0
      cursor += 1
    if ffrpo_raw_scheme_decimal(ptr, token_start, cursor, output, field) == 0
      return 0
    field += 1
  while cursor < finish && ffrpo_status_space(raw_load_u8(ptr, cursor)) != 0
    cursor += 1
  if cursor != finish
    return 0
  1

# Parent-only allocation-free checkpoint loader.  Child search processes keep
# the general catalog loader; the long-lived portfolio uses this equivalent
# parser so its periodic independent exact audits do not retain every line and
# field produced by String#split.
-> ffrpo_load_scheme_cap_raw(state, path, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] String i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  result = 0 - 1 ## i64
  content = read_file(path)
  scratch = i64[3]
  if content != nil
    length = ccall_nobox("w_string_byte_length", content) ## i64
    ptr = ccall_nobox("w_string_byte_ptr", content) ## i64
    data_finish = length ## i64
    # Match String#split's treatment of one ordinary terminal line ending.
    if data_finish > 0 && raw_load_u8(ptr, data_finish - 1) == 10
      data_finish -= 1
      if data_finish > 0 && raw_load_u8(ptr, data_finish - 1) == 13
        data_finish -= 1
    first_finish = 0 ## i64
    while first_finish < data_finish && raw_load_u8(ptr, first_finish) != 10
      first_finish += 1
    first_content_finish = first_finish ## i64
    if first_content_finish > 0 && raw_load_u8(ptr, first_content_finish - 1) == 13
      first_content_finish -= 1
    prefixed = ffrpo_raw_scheme_r_prefix(ptr, 0, first_content_finish) ## i64
    rank = 0 - 1 ## i64
    row_start = first_finish + 1 ## i64
    if prefixed != 0
      row_start = 0
      if data_finish > 0
        rank = 1
        cursor = 0 ## i64
        while cursor < data_finish
          if raw_load_u8(ptr, cursor) == 10
            rank += 1
          cursor += 1
    if prefixed == 0
      token_start = 0 ## i64
      while token_start < first_content_finish && ffrpo_status_space(raw_load_u8(ptr, token_start)) != 0
        token_start += 1
      token_finish = token_start ## i64
      while token_finish < first_content_finish && ffrpo_status_space(raw_load_u8(ptr, token_finish)) == 0
        token_finish += 1
      if ffrpo_raw_scheme_decimal(ptr, token_start, token_finish, scratch, 0) != 0
        rank = scratch[0]
      # The attributed corpus also contains numeric headers followed by
      # `R u v w` rows; preserve the general loader's mixed-format support.
      if row_start < data_finish
        next_finish = row_start ## i64
        while next_finish < data_finish && raw_load_u8(ptr, next_finish) != 10
          next_finish += 1
        prefixed = ffrpo_raw_scheme_r_prefix(ptr, row_start, next_finish)
    ok = 1 ## i64
    if rank < 1 || rank > capacity || row_start > data_finish
      ok = 0
    if ok != 0
      ok = ffr_prepare(state, n, m, p, capacity, seed, dslack, cycles, workq, wanderq)
    if ok != 0
      umask = ffr_factor_mask(n * m) ## i64
      vmask = ffr_factor_mask(m * p) ## i64
      wmask = ffr_factor_mask(n * p) ## i64
      current = 0 ## i64
      row = 0 ## i64
      while row < rank
        if row_start > data_finish
          ok = 0
        row_finish = row_start ## i64
        while row_finish < data_finish && raw_load_u8(ptr, row_finish) != 10
          row_finish += 1
        content_finish = row_finish ## i64
        if content_finish > row_start && raw_load_u8(ptr, content_finish - 1) == 13
          content_finish -= 1
        if ok != 0 && ffrpo_raw_scheme_row(ptr, row_start, content_finish, prefixed, scratch) == 0
          ok = 0
        if ok != 0
          u = scratch[0] ## i64
          v = scratch[1] ## i64
          w = scratch[2] ## i64
          if u <= 0 || (u & umask) != u
            ok = 0
          if v <= 0 || (v & vmask) != v
            ok = 0
          if w <= 0 || (w & wmask) != w
            ok = 0
          if ok != 0
            current = ffw_toggle(state, u, v, w, current)
        if row_finish < data_finish
          row_start = row_finish + 1
        else
          row_start = data_finish + 1
        row += 1
      state[6] = current
      if current != rank
        ok = 0
      if ok != 0
        adopted = ffr_adopt_current(state, 1) ## i64
        if adopted > 0
          state[31] = state[31] + 1
          result = current
        if adopted <= 0
          ok = 0
      if ok == 0
        state[39] = state[39] + 1
  if content != nil
    ccall("w_value_free", content)
  ccall("w_value_free", scratch)
  result

# Load the exact checkpoint when present, otherwise the profile seed.  The
# output row is [rank,bits].  Under --naive the schoolbook seed is used only
# for epoch zero; later epochs recover the portfolio's own durable checkpoint.
-> ffrpo_load_metrics_reuse(tensor, repo_root, best_path, naive, state, output, offset) (String String String i64 i64[] i64[] i64) i64
  n = ffrp_n(tensor) ## i64
  m = ffrp_m(tensor) ## i64
  p = ffrp_p(tensor) ## i64
  if ffr_supported(n, m, p) == 0 || output.size() < offset + 2
    return 0
  capacity = ffr_default_capacity(n, m, p) ## i64
  if state == nil || state.size() < ffr_state_size(capacity)
    return 0
  rank = 0 - 1 ## i64
  if naive != 0
    rank = ffr_init_naive_cap(state, n, m, p, capacity, 91001 + offset, 4, 4, 1000, 250)
  if naive == 0
    checkpoint_size = file_size(best_path)
    if checkpoint_size != nil && checkpoint_size > 0
      rank = ffrpo_load_scheme_cap_raw(state, best_path, n, m, p, capacity, 91003 + offset, 4, 4, 1000, 250)
    if checkpoint_size == nil || checkpoint_size < 1
      seed_path = repo_root + "/" + ffrp_seed_rel(n, m, p)
      rank = ffrpo_load_scheme_cap_raw(state, seed_path, n, m, p, capacity, 91007 + offset, 4, 4, 1000, 250)
  if rank < 1 || ffr_verify_best_exact(state, n, m, p) == 0
    return 0
  output[offset] = ffr_best_rank(state)
  output[offset + 1] = ffr_best_bits(state)
  1

-> ffrpo_load_metrics(tensor, repo_root, best_path, naive, output, offset) (String String String i64 i64[] i64) i64
  n = ffrp_n(tensor) ## i64
  m = ffrp_m(tensor) ## i64
  p = ffrp_p(tensor) ## i64
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  ffrpo_load_metrics_reuse(tensor, repo_root, best_path, naive, state, output, offset)

# Reset one durable shape checkpoint to the exact schoolbook scheme.  The
# coordinator does this for every selected shape at the boundary, even when J
# is smaller than the portfolio and that shape will not receive a CPU worker
# in the current epoch.  Its first later child still receives naive_seed=1 so
# the lower-rank catalog seed cannot immediately replace the requested reset.
-> ffrpo_reset_naive_checkpoint(tensor, best_path, run_tag, nonce, output, offset) (String String String i64 i64[] i64) i64
  n = ffrp_n(tensor) ## i64
  m = ffrp_m(tensor) ## i64
  p = ffrp_p(tensor) ## i64
  if ffr_supported(n, m, p) == 0 || output.size() < offset + 2
    return 0
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = ffr_init_naive_cap(state, n, m, p, capacity, 91501 + offset, 4, 4, 1000, 250) ## i64
  if rank < 1 || ffr_verify_best_exact(state, n, m, p) == 0
    return 0
  output[offset] = ffr_best_rank(state)
  output[offset + 1] = ffr_best_bits(state)
  # Clear first: after a successful reset, even a later process restart must
  # not discover side-door knowledge from the pre-reset campaign.
  if ffrda_clear(best_path, run_tag + "-naive", nonce + 500000) == 0
    return 0
  if ffrc_dump_atomic(state, best_path, run_tag, nonce) < 1
    return 0
  1

# Build the private single-shape invocation used by a portfolio segment.  A
# rectangular campaign allocates one state arena per island plus frontier,
# archive, and accelerator scratch. Tungsten deliberately has no tracing GC,
# so running bounded segments as ordinary threads retained every completed
# arena until the coordinator exited. At large host counts that grew by
# hundreds of GiB over a long portfolio run. Executing the same coordinator in
# a child process gives each segment an allocation lifetime the OS can reclaim
# at its exact epoch boundary.
-> ffrpo_shell_quote_append(command, text)
  if text == nil
    text = ""
  command << "'"
  length = ccall_nobox("w_string_byte_length", text) ## i64
  ptr = ccall_nobox("w_string_byte_ptr", text) ## i64
  has_quote = 0 ## i64
  scan = 0 ## i64
  while scan < length
    if raw_load_u8(ptr, scan) == 39
      has_quote = 1
    scan += 1
  if has_quote == 0
    command << text
    command << "'"
    return 1
  chunk_start = 0 ## i64
  cursor = 0 ## i64
  while cursor < length
    if raw_load_u8(ptr, cursor) == 39
      if cursor > chunk_start
        chunk = text.slice(chunk_start, cursor - chunk_start)
        command << chunk
        ccall("w_value_free", chunk)
      command << "'\"'\"'"
      chunk_start = cursor + 1
    cursor += 1
  if chunk_start < length
    chunk = text.slice(chunk_start, length - chunk_start)
    command << chunk
    ccall("w_value_free", chunk)
  command << "'"
  1

-> ffrpo_child_tag(run_tag, shape_code, epoch, fill_serial) (String i64 i64 i64)
  tag = StringBuffer(96) ## reuse
  tag << run_tag
  tag << "_"
  tag << shape_code
  tag << "_e"
  tag << epoch
  if fill_serial >= 0
    tag << "_f"
    tag << fill_serial
  result = tag.to_s()
  result

-> ffrpo_child_command(worker_binary, tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket)
  if worker_binary == nil || worker_binary == ""
    return ""
  command = StringBuffer(768) ## reuse
  z = ffrpo_shell_quote_append(command, worker_binary)
  command << " --tensor "
  z = ffrpo_shell_quote_append(command, tensor)
  command << " --runtime-root "
  z = ffrpo_shell_quote_append(command, repo_root)
  command << " --best "
  z = ffrpo_shell_quote_append(command, best_path)
  command << " --status "
  z = ffrpo_shell_quote_append(command, status_path)
  command << " --run-tag "
  z = ffrpo_shell_quote_append(command, child_tag)
  command << " -J "
  command << walkers
  command << " --steps "
  command << steps
  command << " --rounds "
  command << epoch_rounds
  command << " --secs "
  command << max_secs
  command << " -d "
  command << dslack
  command << " --cycles "
  command << cycles
  command << " --gpu-walkers "
  command << gpu_lanes
  command << " --gpu-steps "
  command << gpu_steps
  command << " --gpu-epoch-rounds "
  command << gpu_epoch_rounds
  if gpu_binary != nil && gpu_binary != ""
    command << " --gpu-binary "
    z = ffrpo_shell_quote_append(command, gpu_binary)
  if gpu_requested != 0
    command << " --gpu"
  if gpu_requested == 0
    command << " --no-gpu"
  if gpu_rebuild != 0
    command << " --rebuild-gpu"
  if stop_on_record != 0
    command << " --stop-on-record"
  if naive_seed != 0
    command << " --naive"
  command << " --quiet --no-tui --rect-portfolio-child"
  command << " --rect-restart-nonce "
  restart_nonce_text = restart_nonce.to_s()
  command << restart_nonce_text
  ccall("w_value_free", restart_nonce_text)
  command << " --rect-door-ticket "
  command << restart_door_ticket
  # Keep diagnostics out of the parent's TUI while retaining the most recent
  # failed child output next to the machine-readable status file.
  command << " > "
  child_log_path = status_path + ".child.log"
  z = ffrpo_shell_quote_append(command, child_log_path)
  ccall("w_value_free", child_log_path)
  command << " 2>&1"
  result = command.to_s()
  result

# One launcher per shape stays alive for the portfolio lifetime. Besides
# avoiding pthread setup at every epoch, this bounds parent-side TLS/stack
# caches that otherwise grew by roughly 95 KiB per short segment even after
# the search arena itself moved into a child process.
-> ffrpo_start_process_launcher(commands, states, exit_codes, elapsed_ms, slot)
  Thread.new ->
    while states[slot] >= 0
      if states[slot] == 1
        command = commands[slot]
        started = ccall("__w_clock_ms") ## i64
        ok = system(command)
        code = 2 ## i64
        if ok
          code = 0
        exit_codes[slot] = code
        elapsed_ms[slot] = ccall("__w_clock_ms") - started
        # The command is an exact one-shot handoff. Clear the shared slot
        # before releasing its heap string, then publish completion last.
        commands[slot] = ""
        ccall("w_value_free", command)
        states[slot] = 2
      if states[slot] != 1 && states[slot] >= 0
        ccall("__w_sleep_ms", 2)
    true

-> ffrpo_dispatch_shape(worker_binary, launcher_threads, launcher_commands, launcher_states, tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket, exit_codes, elapsed_ms, slot)
  if worker_binary != nil && worker_binary != ""
    if launcher_states[slot] != 0 || launcher_threads[slot] == nil
      return nil
    command = ffrpo_child_command(worker_binary, tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket)
    if command == ""
      return nil
    launcher_commands[slot] = command
    launcher_states[slot] = 1
    return launcher_threads[slot]
  ffrpo_spawn_shape("", tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket, exit_codes, elapsed_ms, slot)

-> ffrpo_spawn_shape(worker_binary, tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket, exit_codes, elapsed_ms, slot) (String String String String String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64 i64 i64 i64 i64[] i64[] i64)
  command = ffrpo_child_command(worker_binary, tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, restart_nonce, restart_door_ticket)
  if command != ""
    return Thread.new ->
      started = ccall("__w_clock_ms") ## i64
      ok = system(command)
      code = 2 ## i64
      if ok
        code = 0
      exit_codes[slot] = code
      elapsed_ms[slot] = ccall("__w_clock_ms") - started
      true
  # Retain an explicit in-process fallback for small embedding tests that
  # import `portfolio.w` without compiling the Metaflip CLI as their main
  # executable. Production always supplies System.executable_path().
  Thread.new ->
    started = ccall("__w_clock_ms") ## i64
    code = ffrc_run_seeded(tensor, repo_root, "", best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, 0, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, 1, 0, stop_on_record, naive_seed, 1, restart_nonce, restart_door_ticket) ## i64
    exit_codes[slot] = code
    elapsed_ms[slot] = ccall("__w_clock_ms") - started
    true

-> ffrpo_segment_alive(worker_binary, thread, launcher_states, slot) i64
  if worker_binary != nil && worker_binary != ""
    if launcher_states[slot] == 1
      return 1
    return 0
  if thread != nil && thread.alive?
    return 1
  0

-> ffrpo_segment_finished(worker_binary, thread, launcher_states, slot) i64
  if worker_binary != nil && worker_binary != ""
    if launcher_states[slot] == 2
      return 1
    return 0
  if thread != nil && thread.alive? == false
    return 1
  0

-> ffrpo_finish_segment(worker_binary, thread, launcher_states, slot) i64
  if worker_binary != nil && worker_binary != ""
    if launcher_states[slot] != 2
      return 0
    launcher_states[slot] = 0
    return 1
  joined = ffrc_thread_join_release(thread)
  if joined == true
    return 1
  0

-> ffrpo_any_alive(threads, worker_binary, launcher_states)
  i = 0 ## i64
  while i < threads.size()
    thread = threads[i]
    if ffrpo_segment_alive(worker_binary, thread, launcher_states, i) != 0
      return 1
    i += 1
  0

# A terminal interrupt cancels the wait thread, whose runtime cleanup owns and
# reaps the shell's entire process group. This makes SIGINT/SIGTERM prompt and
# prevents a second signal or supervisor timeout from orphaning a rectangular
# Metaflip child. Record which leases the parent deliberately cancelled: that
# synthetic exit code is not a failed finite lease. TUI `q` remains the
# graceful drain path.
-> ffrpo_cancel_active_segments(worker_binary, threads, launcher_threads, launcher_states, segment_joined, exit_codes, parent_cancelled) i64
  cancelled = 0 ## i64
  i = 0 ## i64
  while i < threads.size()
    thread = threads[i]
    alive = ffrpo_segment_alive(worker_binary, thread, launcher_states, i) ## i64
    if thread != nil && alive != 0
      z = thread.kill
      joined = ffrc_thread_join_release(thread)
      threads[i] = nil
      segment_joined[i] = 1
      exit_codes[i] = 2
      parent_cancelled[i] = 1
      if worker_binary != nil && worker_binary != ""
        launcher_threads[i] = nil
        launcher_states[i] = 0 - 2
      cancelled += 1
    i += 1
  cancelled

-> ffrpo_stop_process_launchers(worker_binary, launcher_threads, launcher_states) i64
  if worker_binary == nil || worker_binary == ""
    return 0
  stopped = 0 ## i64
  i = 0 ## i64
  while i < launcher_threads.size()
    if launcher_threads[i] != nil
      launcher_states[i] = 0 - 1
    i += 1
  i = 0
  while i < launcher_threads.size()
    launcher = launcher_threads[i]
    if launcher != nil
      joined = ffrc_thread_join_release(launcher)
      launcher_threads[i] = nil
      stopped += 1
    i += 1
  stopped

# First-stage terminal gate for a private lease. An exit synthesized by the
# portfolio parent while responding to TERM/INT/HUP is a cancellation, not a
# failed finite lease. Cancellation only relaxes the two observations that the
# parent itself manufactured (nonzero exit and no harvested work); exact
# rejects and every later checkpoint/exact audit remain fail-closed.
-> ffrpo_segment_precheck_failed(launched, exit_code, exact_rejects, wall_ms, cpu_moves, parent_cancelled) (i64 i64 i64 i64 i64 i64) i64
  if launched == 0
    return 1
  if exit_code != 0 && parent_cancelled == 0
    return 1
  if exact_rejects > 0
    return 1
  if wall_ms < 1 && cpu_moves < 1 && parent_cancelled == 0
    return 1
  0

-> ffrpo_commit_operational(shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, slot, cpu_moves, gpu_moves, mitm_attempts, mitm_pairs, mitm_ms, mitm_failures, failed)
  # Work counters describe computation that happened, not whether the segment
  # later passed its exit/checkpoint gate. Keep them monotone even for failed
  # segments; `failed` is deliberately not a reason to discard the work.
  if slot < 0 || slot >= shape_cpu_moves.size()
    return 0
  if cpu_moves < 0
    cpu_moves = 0
  if gpu_moves < 0
    gpu_moves = 0
  if mitm_attempts < 0
    mitm_attempts = 0
  if mitm_pairs < 0
    mitm_pairs = 0
  if mitm_ms < 0
    mitm_ms = 0
  if mitm_failures < 0
    mitm_failures = 0
  shape_cpu_moves[slot] += cpu_moves
  shape_gpu_moves[slot] += gpu_moves
  shape_mitm_attempts[slot] += mitm_attempts
  shape_mitm_pairs[slot] += mitm_pairs
  shape_mitm_ms[slot] += mitm_ms
  shape_mitm_failures[slot] += mitm_failures
  cpu_moves + gpu_moves

-> ffrpo_status_body(state_name, sequence, epoch, elapsed_s, total_j, total_gpu, total_moves, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, shape_moves, shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, exposure, failures, gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
  health = "ok"
  if degraded != 0
    health = "degraded"
  total_cpu_moves = 0 ## i64
  total_gpu_moves = 0 ## i64
  total_mitm_attempts = 0 ## i64
  total_mitm_pairs = 0 ## i64
  total_mitm_ms = 0 ## i64
  total_mitm_failures = 0 ## i64
  i = 0 ## i64
  while i < labels.size()
    total_cpu_moves += shape_cpu_moves[i]
    total_gpu_moves += shape_gpu_moves[i]
    total_mitm_attempts += shape_mitm_attempts[i]
    total_mitm_pairs += shape_mitm_pairs[i]
    total_mitm_ms += shape_mitm_ms[i]
    total_mitm_failures += shape_mitm_failures[i]
    i += 1
  body = StringBuffer(512 + labels.size() * 512) ## reuse
  body << "schema=1 mode=rect-portfolio producer_state="
  body << state_name
  body << " sequence="
  body << sequence
  body << " epoch="
  body << epoch
  body << " elapsed="
  body << elapsed_s
  body << " cpu_lanes="
  body << total_j
  body << " gpu_lanes="
  body << total_gpu
  body << " shapes="
  body << labels.size()
  body << " total_moves="
  body << total_moves
  body << " total_cpu_moves="
  body << total_cpu_moves
  body << " total_gpu_moves="
  body << total_gpu_moves
  body << " total_mitm_attempts="
  body << total_mitm_attempts
  body << " total_mitm_pairs="
  body << total_mitm_pairs
  body << " total_mitm_ms="
  body << total_mitm_ms
  body << " total_mitm_failures="
  body << total_mitm_failures
  body << " health="
  body << health
  body << "\n"
  i = 0 ## i64
  while i < labels.size()
    combined_failures = failures[i] + gpu_failures[i] + shape_mitm_failures[i] ## i64
    body << "shape="
    body << labels[i]
    body << " ready="
    body << ready[i]
    body << " cpu="
    body << cpu_allocation[i]
    body << " gpu="
    body << gpu_allocation[i]
    body << " rank="
    body << ranks[i]
    body << " bits="
    body << bits[i]
    body << " drops="
    body << rank_drops[i]
    body << " density="
    body << density_gains[i]
    body << " moves="
    body << shape_moves[i]
    body << " cpu_moves="
    body << shape_cpu_moves[i]
    body << " gpu_moves="
    body << shape_gpu_moves[i]
    body << " mitm_attempts="
    body << shape_mitm_attempts[i]
    body << " mitm_pairs="
    body << shape_mitm_pairs[i]
    body << " mitm_ms="
    body << shape_mitm_ms[i]
    body << " mitm_failures="
    body << shape_mitm_failures[i]
    body << " exposure="
    body << exposure[i]
    body << " failures="
    body << combined_failures
    body << " cpu_failures="
    body << failures[i]
    body << " gpu_failures="
    body << gpu_failures[i]
    body << " score="
    body << scores[i]
    body << " side_archive_loaded="
    body << side_loaded[i]
    body << " side_archive_seeded="
    body << side_seeded[i]
    body << " side_archive_saved="
    body << side_saved[i]
    body << " side_archive_rejects="
    body << side_rejects[i]
    body << " side_archive_write_failures="
    body << side_write_failures[i]
    body << "\n"
    i += 1
  result = body.to_s()
  result

# A rectangular cal2zone child reaches full occupancy at about 8192 logical
# walkers on the reference Apple GPU. Splitting that width between several
# independent Metal processes measured slower than rotating one full-width
# child. Scale concurrency only when the requested lane budget can preserve
# this occupancy floor for every active child.
-> ffrpo_gpu_child_floor_lanes() i64
  8192

-> ffrpo_gpu_adaptive_limit(total_lanes, ready) (i64 i64[]) i64
  if total_lanes < 16
    return 0
  live = ffrpp_ready_count(ready, ready.size()) ## i64
  if live < 1
    return 0
  limit = total_lanes / ffrpo_gpu_child_floor_lanes() ## i64
  if limit < 1
    limit = 1
  if limit > live
    limit = live
  limit

# Pick the highest adaptive score, rotating equal-score priority by epoch.
# `selected` is both an exclusion mask and the output membership set.
-> ffrpo_gpu_pick(epoch, ready, selected, scores) (i64 i64[] i64[] i64[]) i64
  count = ready.size() ## i64
  if selected.size() < count || scores.size() < count || count < 1
    return 0 - 1
  tie_start = epoch % count ## i64
  if tie_start < 0
    tie_start += count
  best = 0 - 1 ## i64
  i = 0 ## i64
  while i < count
    if ready[i] != 0 && selected[i] == 0
      if best < 0 || scores[i] > scores[best]
        best = i
      if best >= 0 && scores[i] == scores[best]
        i_key = (i - tie_start + count) % count ## i64
        best_key = (best - tie_start + count) % count ## i64
        if i_key < best_key
          best = i
    i += 1
  if best >= 0
    selected[best] = 1
  best

-> ffrpo_gpu_allocate(total_lanes, epoch, policy, shapes, ready, rank_drops, density_gains, leverage, exposure, failures, allocation, scores) (i64 i64 String i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = shapes.size() ## i64
  units = total_lanes / 16 ## i64
  zero_gpu_discount = i64[count]
  score_scratch = i64[count]
  selected = i64[count]
  unit_allocation = i64[count]
  # One logical allocation is enough to make the pure policy calculate every
  # ready shape's empirical/exploration score. The returned allocation is not
  # used: GPU occupancy has a separate, coarser concurrency rule below.
  scored = ffrpp_allocate(1, epoch, shapes, ready, zero_gpu_discount, rank_drops, density_gains, leverage, exposure, failures, score_scratch, scores) ## i64
  i = 0 ## i64
  while i < count
    allocation[i] = 0
    i += 1
  if scored <= 0 || units < 1
    return 0

  active_limit = 1 ## i64
  if policy != "single"
    active_limit = ffrpo_gpu_adaptive_limit(units * 16, ready)
  active_count = 0 ## i64
  while active_count < active_limit
    best = ffrpo_gpu_pick(epoch + active_count, ready, selected, scores) ## i64
    if best < 0
      break
    active_count += 1
  if active_count < 1
    return 0

  # `single` is deliberately full-width regardless of the adaptive occupancy
  # cap. It shares the same score and rotated-tie selection as adaptive mode.
  if policy == "single"
    i = 0
    while i < count
      if selected[i] != 0
        allocation[i] = units * 16
        return allocation[i]
      i += 1
    return 0

  floor_units = ffrpo_gpu_child_floor_lanes() / 16 ## i64
  if units < floor_units
    floor_units = units
  used = 0 ## i64
  i = 0
  while i < count
    if selected[i] != 0
      unit_allocation[i] = floor_units
      used += floor_units
    i += 1

  # The limit construction guarantees the floors fit. Keep a defensive
  # fallback for future callers that use a non-normalized lane count.
  if used > units
    i = 0
    used = 0
    while i < count
      if selected[i] != 0
        unit_allocation[i] = 0
      i += 1
    while used < units
      i = 0
      while i < count && used < units
        if selected[i] != 0
          unit_allocation[i] += 1
          used += 1
        i += 1

  # Assign capacity above the occupancy floors by the same D'Hondt score used
  # by the CPU policy. Floors keep every launched child efficient; scores keep
  # productive shapes favored without starving the selected exploration set.
  tie_start = epoch % count ## i64
  if tie_start < 0
    tie_start += count
  while used < units
    best = 0 - 1 ## i64
    i = 0
    while i < count
      if selected[i] != 0
        if best < 0
          best = i
        else
          left = scores[i] * (unit_allocation[best] + 1) ## i64
          right = scores[best] * (unit_allocation[i] + 1) ## i64
          if left > right
            best = i
          if left == right
            i_key = (i - tie_start + count) % count ## i64
            best_key = (best - tie_start + count) % count ## i64
            if i_key < best_key
              best = i
      i += 1
    if best < 0
      break
    unit_allocation[best] += 1
    used += 1

  i = 0
  while i < count
    allocation[i] = unit_allocation[i] * 16
    i += 1
  used * 16

# Keep the GPU useful on very small portfolios: if CPU floor rotation selected
# only CPU-only shapes, move one already-budgeted CPU host slot to a supported
# GPU shape. Total J remains exact; the GPU host rotates across eligible shapes.
-> ffrpo_ensure_gpu_host(epoch, gpu_ready, allocation, scores)
  count = allocation.size() ## i64
  live_gpu = 0 ## i64
  total_cpu = 0 ## i64
  i = 0 ## i64
  while i < count
    total_cpu += allocation[i]
    if i < gpu_ready.size() && gpu_ready[i] != 0
      live_gpu += 1
      if allocation[i] > 0
        return 0
    i += 1
  if total_cpu < 1 || live_gpu < 1
    return 0
  wanted = epoch % live_gpu ## i64
  if wanted < 0
    wanted += live_gpu
  target = 0 - 1 ## i64
  ordinal = 0 ## i64
  i = 0
  while i < count && target < 0
    if i < gpu_ready.size() && gpu_ready[i] != 0
      if ordinal == wanted
        target = i
      ordinal += 1
    i += 1
  donor = 0 - 1 ## i64
  i = 0
  while i < count
    if allocation[i] > 0 && i != target
      if donor < 0 || allocation[i] > allocation[donor]
        donor = i
      if donor >= 0 && allocation[i] == allocation[donor] && i < scores.size() && donor < scores.size() && scores[i] < scores[donor]
        donor = i
    i += 1
  if target < 0 || donor < 0
    return 0
  allocation[donor] -= 1
  allocation[target] += 1
  1

-> ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, status_degraded)
  if status_degraded != 0
    return 1
  i = 0 ## i64
  while i < permanent_failure.size()
    if permanent_failure[i] != 0 || hard_degraded[i] != 0 || gpu_degraded[i] != 0 || side_degraded[i] != 0
      return 1
    i += 1
  0

-> ffrpo_render_rows(rows)
  frame = "\e[?2026h\e[H"
  i = 0 ## i64
  while i < rows.size()
    frame = frame + rows[i] + "\e[K\n"
    i += 1
  frame = frame + "\e[J\e[?2026l"
  << frame
  flush()
  1

-> ffrpo_frame_rows(labels, cpu_allocation, gpu_allocation, ranks, initial_ranks, bits, rank_drops, density_gains, scores, exposure, failures, gpu_states, active, ages, run_elapsed, epoch, elapsed_s, total_j, active_j, total_gpu, active_gpu, total_moves, ready_count, degraded, flash_text, width)
  rows = []
  inner = width - 2 ## i64
  if inner < 0
    inner = 0
  health = "RUNNING"
  health_code = "1;32"
  if degraded != 0
    health = "DEGRADED"
    health_code = "1;33"
  title_plain = "  metaflip  rectangular portfolio GF(2)   " + health
  title_painted = "  " + ff_tui_paint("metaflip", "1;33") + "  rectangular portfolio GF(2)   " + ff_tui_paint(health, health_code)
  rows.push(ff_tui_fit(title_plain, title_painted, width))
  stat_plain = ["  epoch " + epoch.to_s(), "   elapsed " + ff_tui_duration(elapsed_s), "   CPU " + active_j.to_s() + "/" + total_j.to_s(), "   GPU " + active_gpu.to_s() + "/" + total_gpu.to_s(), "   shapes " + ready_count.to_s() + "/" + labels.size().to_s(), "   moves " + ff_tui_compact_fixed(total_moves, 6)]
  stat_painted = ["  " + ff_tui_dim("epoch") + " " + epoch.to_s(), "   " + ff_tui_dim("elapsed") + " " + ff_tui_duration(elapsed_s), "   " + ff_tui_dim("CPU") + " " + active_j.to_s() + "/" + total_j.to_s(), "   " + ff_tui_dim("GPU") + " " + active_gpu.to_s() + "/" + total_gpu.to_s(), "   " + ff_tui_dim("shapes") + " " + ready_count.to_s() + "/" + labels.size().to_s(), "   " + ff_tui_dim("moves") + " " + ff_tui_compact_fixed(total_moves, 6)]
  rows.push(ff_tui_join_fit(stat_plain, stat_painted, width))
  if flash_text != ""
    rows.push("  " + ff_tui_paint(ff_tui_clip(flash_text, inner), "1;33"))
  rows.push("")
  section = ffrpt_frame_rows("Rectangular shapes (independent exact campaigns)", labels, cpu_allocation, gpu_allocation, ranks, initial_ranks, bits, rank_drops, density_gains, scores, exposure, failures, gpu_states, active, ages, run_elapsed, width)
  i = 0 ## i64
  while i < section.size()
    rows.push(section[i])
    i += 1
  rows.push("")
  footer = ff_tui_clip("allocations change only at exact epoch boundaries · fast shapes fill until slowest base rounds finish · space=reset every shape to naive · q/Ctrl-C stops after the current epoch", inner)
  rows.push("  " + ff_tui_dim(footer))
  rows

# Run several exact rectangular campaigns concurrently. `max_epochs` counts
# portfolio reallocations; each shape keeps its sticky islands for
# `shape_epoch_rounds` ordinary rectangular rounds before the exact restart.
-> ffrpo_run(shape_spec, repo_root, state_dir, best_base, best_explicit, status_path, status_explicit, run_tag, total_j, steps, max_epochs, max_secs, shape_epoch_rounds, dslack, cycles, gpu_requested, total_gpu_lanes, gpu_policy, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, quiet, tui, stop_on_record, naive_seed, worker_binary) (String String String String i64 String i64 String i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64 String i64 i64 i64 i64 i64 String) i64
  labels = []
  code_storage = i64[32]
  count = ffrpo_parse_shapes(shape_spec, labels, code_storage) ## i64
  if count < 1
    << "RECT_PORTFOLIO_ERROR code=shapes value=" + shape_spec
    return 2
  if total_gpu_lanes < 0 || gpu_requested == 0
    total_gpu_lanes = 0
  total_gpu_lanes = (total_gpu_lanes / 16) * 16
  if quiet == 0 && tui == 0
    << "RECT_PORTFOLIO_CAPABILITY state=initializing shapes=" + count.to_s() + " cpu=" + total_j.to_s() + " gpu=" + total_gpu_lanes.to_s()
    flush()
  shapes = i64[count]
  i = 0 ## i64
  while i < count
    shapes[i] = code_storage[i]
    i += 1

  ready = i64[count]
  permanent_failure = i64[count]
  retry_epoch = i64[count]
  gpu_supported = i64[count]
  gpu_sched_ready = i64[count]
  gpu_launch_ready = i64[count]
  gpu_retry_epoch = i64[count]
  gpu_failures = i64[count]
  hard_degraded = i64[count]
  gpu_degraded = i64[count]
  side_degraded = i64[count]
  gpu_states = i64[count]
  leverage = i64[count]
  rank_drops = i64[count]
  density_gains = i64[count]
  exposure = i64[count]
  failures = i64[count]
  rewards = i64[count]
  scores = i64[count]
  gpu_scores = i64[count]
  cpu_allocation = i64[count]
  gpu_allocation = i64[count]
  ranks = i64[count]
  initial_ranks = i64[count]
  bits = i64[count]
  last_progress_ms = i64[count]
  ages = i64[count]
  run_elapsed = i64[count]
  shape_moves = i64[count]
  shape_cpu_moves = i64[count]
  shape_gpu_moves = i64[count]
  shape_mitm_attempts = i64[count]
  shape_mitm_pairs = i64[count]
  shape_mitm_ms = i64[count]
  shape_mitm_failures = i64[count]
  side_loaded = i64[count]
  side_seeded = i64[count]
  side_saved = i64[count]
  side_rejects = i64[count]
  side_write_failures = i64[count]
  active = i64[count]
  exit_codes = i64[count]
  child_elapsed_ms = i64[count]
  reset_pending = i64[count]
  reset_children = i64[count]
  display_ranks = i64[count]
  display_bits = i64[count]
  display_rank_drops = i64[count]
  display_density_gains = i64[count]
  display_rewards = i64[count]
  display_shape_moves = i64[count]
  display_shape_cpu_moves = i64[count]
  display_shape_gpu_moves = i64[count]
  display_shape_mitm_attempts = i64[count]
  display_shape_mitm_pairs = i64[count]
  display_shape_mitm_ms = i64[count]
  display_shape_mitm_failures = i64[count]
  display_exposure = i64[count]
  display_failures = i64[count]
  display_cpu_failures = i64[count]
  display_gpu_failures = i64[count]
  display_ages = i64[count]
  display_elapsed = i64[count]
  child_status_values = i64[19]
  best_paths = []
  child_status_paths = []
  metric_states = []

  if status_explicit == 0
    if ffls_ensure_dir(ffls_run_dir(state_dir, "gf2", "rect", run_tag)) == 0
      << "RECT_PORTFOLIO_ERROR code=state-status-dir"
      return 2

  start_ms = ccall("__w_clock_ms") ## i64
  valid = 0 ## i64
  metrics = i64[count * 2]
  i = 0
  while i < count
    tensor = labels[i]
    n = ffrp_n(tensor) ## i64
    m = ffrp_m(tensor) ## i64
    p = ffrp_p(tensor) ## i64
    path = ffrpo_best_path(best_base, best_explicit, tensor, state_dir)
    child_status_path = ffrpo_child_status_path(status_path, status_explicit, tensor, state_dir, run_tag)
    if best_explicit == 0
      if ffls_ensure_dir(ffls_checkpoint_dir(state_dir, "gf2", tensor)) == 0
        << "RECT_PORTFOLIO_ERROR code=state-checkpoint-dir tensor=" + tensor
        return 2
    if status_explicit == 0
      if ffls_ensure_dir(ffls_run_dir(state_dir, "gf2", tensor, run_tag)) == 0
        << "RECT_PORTFOLIO_ERROR code=state-child-status-dir tensor=" + tensor
        return 2
    best_paths.push(path)
    child_status_paths.push(child_status_path)
    metric_capacity = ffr_default_capacity(n, m, p) ## i64
    metric_state = i64[ffr_state_size(metric_capacity)]
    metric_states.push(metric_state)
    leverage[i] = ffrpp_default_leverage(shapes[i])
    gpu_supported[i] = ffrgb_supported(n, m, p)
    gpu_states[i] = 0 - 1
    if gpu_supported[i] != 0
      gpu_states[i] = 1
    loaded = ffrpo_load_metrics_reuse(tensor, repo_root, path, naive_seed, metric_state, metrics, i * 2) ## i64
    if loaded != 0
      ready[i] = 1
      ranks[i] = metrics[i * 2]
      bits[i] = metrics[i * 2 + 1]
      initial_ranks[i] = ranks[i]
      valid += 1
    if loaded == 0
      permanent_failure[i] = 1
      hard_degraded[i] = 1
      failures[i] = 1
      ranks[i] = 0 - 1
      bits[i] = 0 - 1
      initial_ranks[i] = 0 - 1
    last_progress_ms[i] = start_ms
    i += 1
  if valid == 0
    << "RECT_PORTFOLIO_ERROR code=no-exact-seeds"
    return 2
  if quiet == 0 && tui == 0
    << "RECT_PORTFOLIO_CAPABILITY state=ready exact_shapes=" + valid.to_s() + "/" + count.to_s()
    flush()

  if shape_epoch_rounds < 1
    shape_epoch_rounds = 1

  ccall("__w_trap_interrupts")
  if tui != 0
    ccall("w_term_raw_enable")
  epoch = 0 ## i64
  sequence = 0 ## i64
  total_moves = 0 ## i64
  running = 1 ## i64
  stop_requested = 0 ## i64
  reset_next = naive_seed ## i64
  reset_requested = 0 ## i64
  degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, 0) ## i64
  status_degraded = 0 ## i64
  last_render_ms = 0 - 1 ## i64
  last_parent_status_ms = 0 - 1 ## i64
  flash_text = ""
  portfolio_write_tag = run_tag + "_portfolio"
  launcher_commands = []
  launcher_states = i64[count]
  launcher_threads = []
  i = 0
  while i < count
    launcher_commands.push("")
    launcher = nil
    if worker_binary != nil && worker_binary != ""
      launcher = ffrpo_start_process_launcher(launcher_commands, launcher_states, exit_codes, child_elapsed_ms, i)
    launcher_threads.push(launcher)
    i += 1

  # Reuse the complete epoch-accounting workspace. These arrays are tiny next
  # to a search state, but allocating a new set at every portfolio boundary
  # still made a no-work stress test grow linearly after the large verifier
  # arena was fixed.
  threads = []
  segment_joined = i64[count]
  parent_cancelled = i64[count]
  base_complete = i64[count]
  base_wall_ms = i64[count]
  total_rounds = i64[count]
  total_wall_ms = i64[count]
  acc_cpu_moves = i64[count]
  acc_gpu_moves = i64[count]
  acc_cpu_ms = i64[count]
  acc_gpu_ms = i64[count]
  acc_mitm_attempts = i64[count]
  acc_mitm_pairs = i64[count]
  acc_mitm_ms = i64[count]
  acc_mitm_failures = i64[count]
  acc_child_degraded = i64[count]
  acc_gpu_failures = i64[count]
  acc_exact_rejects = i64[count]
  reported_ranks = i64[count]
  reported_bits = i64[count]
  reported_terminal = i64[count]
  fill_serial = i64[count]
  launched = i64[count]
  child_gpu_flags = i64[count]
  i = 0
  while i < count
    threads.push(nil)
    i += 1

  while running != 0
    now_ms = ccall("__w_clock_ms") ## i64
    elapsed_s = (now_ms - start_ms) / 1000 ## i64
    if max_secs > 0 && elapsed_s >= max_secs
      break
    child_max_secs = 0 ## i64
    if max_secs > 0
      child_max_secs = max_secs - elapsed_s
      if child_max_secs < 1
        child_max_secs = 1
    reset_epoch = reset_next ## i64
    reset_next = 0
    if reset_epoch != 0
      reset_write_failures = 0 ## i64
      i = 0
      while i < count
        reset_pending[i] = 1
        if permanent_failure[i] == 0
          z = ffrpo_reset_naive_checkpoint(labels[i], best_paths[i], run_tag, 700000 + epoch * 64 + i, metrics, i * 2) ## i64
          if z != 0
            ranks[i] = metrics[i * 2]
            bits[i] = metrics[i * 2 + 1]
            initial_ranks[i] = ranks[i]
            hard_degraded[i] = 0
          if z == 0
            failures[i] += 1
            hard_degraded[i] = 1
            reset_write_failures += 1
        rank_drops[i] = 0
        density_gains[i] = 0
        exposure[i] = 0
        rewards[i] = 0
        shape_moves[i] = 0
        shape_cpu_moves[i] = 0
        shape_gpu_moves[i] = 0
        shape_mitm_attempts[i] = 0
        shape_mitm_pairs[i] = 0
        shape_mitm_ms[i] = 0
        # Failure history is monotone across a naive objective reset, matching
        # `failures` and `gpu_failures`; health itself may recover after a
        # later clean observed epoch.
        side_loaded[i] = 0
        side_seeded[i] = 0
        side_saved[i] = 0
        side_rejects[i] = 0
        side_write_failures[i] = 0
        side_degraded[i] = 0
        last_progress_ms[i] = now_ms
        i += 1
      total_moves = 0
      flash_text = "all rectangular bests and rank timelines reset to naive"
      if reset_write_failures > 0
        flash_text = "naive reset queued; " + reset_write_failures.to_s() + " checkpoint writes will retry in their child"

    i = 0
    while i < count
      ready[i] = 0
      if permanent_failure[i] == 0 && epoch >= retry_epoch[i]
        ready[i] = 1
      gpu_sched_ready[i] = 0
      gpu_states[i] = 0 - 1
      if gpu_supported[i] != 0
        gpu_states[i] = 0
        if ready[i] != 0 && epoch >= gpu_retry_epoch[i] && gpu_requested != 0
          gpu_sched_ready[i] = 1
          gpu_states[i] = 1
      i += 1

    allocated = ffrpp_allocate(total_j, epoch, shapes, ready, gpu_sched_ready, rank_drops, density_gains, leverage, exposure, failures, cpu_allocation, scores) ## i64
    if allocated < 0
      if tui != 0
        ccall("w_term_raw_disable")
      << "RECT_PORTFOLIO_ERROR code=cpu-allocation"
      stopped_launchers = ffrpo_stop_process_launchers(worker_binary, launcher_threads, launcher_states) ## i64
      return 2
    if total_gpu_lanes > 0 && gpu_requested != 0
      z = ffrpo_ensure_gpu_host(epoch, gpu_sched_ready, cpu_allocation, scores) ## i64
    i = 0
    while i < count
      gpu_launch_ready[i] = 0
      if gpu_sched_ready[i] != 0 && cpu_allocation[i] > 0
        gpu_launch_ready[i] = 1
      i += 1
    gpu_allocated = ffrpo_gpu_allocate(total_gpu_lanes, epoch, gpu_policy, shapes, gpu_launch_ready, rank_drops, density_gains, leverage, exposure, gpu_failures, gpu_allocation, gpu_scores) ## i64
    if quiet == 0 && tui == 0
      << "RECT_PORTFOLIO_CAPABILITY state=launch epoch=" + epoch.to_s() + " cpu=" + allocated.to_s() + " gpu=" + gpu_allocated.to_s()
      flush()

    # Per-shape epoch accounting for base quota + optional straggler-fill rounds.
    i = 0
    while i < count
      exit_codes[i] = 0
      child_elapsed_ms[i] = 0
      reset_children[i] = 0
      active[i] = 0
      segment_joined[i] = 1
      parent_cancelled[i] = 0
      base_complete[i] = 0
      base_wall_ms[i] = 0
      total_rounds[i] = 0
      total_wall_ms[i] = 0
      acc_cpu_moves[i] = 0
      acc_gpu_moves[i] = 0
      acc_cpu_ms[i] = 0
      acc_gpu_ms[i] = 0
      acc_mitm_attempts[i] = 0
      acc_mitm_pairs[i] = 0
      acc_mitm_ms[i] = 0
      acc_mitm_failures[i] = 0
      acc_child_degraded[i] = 0
      acc_gpu_failures[i] = 0
      acc_exact_rejects[i] = 0
      reported_ranks[i] = 0 - 1
      reported_bits[i] = 0 - 1
      reported_terminal[i] = 0
      fill_serial[i] = 0
      launched[i] = 0
      child_gpu_flags[i] = 0
      thread = nil
      if cpu_allocation[i] > 0 && ready[i] != 0
        reset_children[i] = reset_pending[i]
        child_tag = ffrpo_child_tag(run_tag, shapes[i], epoch, 0 - 1)
        child_gpu = 0 ## i64
        if gpu_allocation[i] > 0 && gpu_sched_ready[i] != 0
          child_gpu = 1
        child_gpu_flags[i] = child_gpu
        rebuild = 0 ## i64
        if epoch == 0 && gpu_rebuild != 0
          rebuild = 1
        cleared = write_file(child_status_paths[i], "")
        if cleared
          active[i] = 1
          launched[i] = 1
          segment_joined[i] = 0
          restart_nonce = ffrcb_portfolio_nonce(epoch, i, 0) ## i64
          restart_door_ticket = ffrcb_portfolio_door_ticket(epoch, i, 0) ## i64
          thread = ffrpo_dispatch_shape(worker_binary, launcher_threads, launcher_commands, launcher_states, labels[i], repo_root, best_paths[i], child_status_paths[i], child_tag, cpu_allocation[i], steps, shape_epoch_rounds, child_max_secs, dslack, cycles, child_gpu, gpu_allocation[i], gpu_steps, gpu_epoch_rounds, ffrpo_gpu_binary(gpu_binary, labels[i]), rebuild, stop_on_record, reset_children[i], restart_nonce, restart_door_ticket, exit_codes, child_elapsed_ms, i)
          if thread == nil
            exit_codes[i] = 2
            segment_joined[i] = 1
            base_complete[i] = 1
        if cleared == false
          exit_codes[i] = 2
          launched[i] = 1
          segment_joined[i] = 1
          base_complete[i] = 1
        if worker_binary != nil && worker_binary != ""
          ccall("w_value_free", child_tag)
      threads[i] = thread
      i += 1

    epoch_started_ms = ccall("__w_clock_ms") ## i64
    epoch_running = 1 ## i64
    while epoch_running != 0
      now_ms = ccall("__w_clock_ms") ## i64
      elapsed_s = (now_ms - start_ms) / 1000

      # Harvest finished segments and optionally start one-round straggler fills.
      deadline_ms = epoch_started_ms ## i64
      i = 0
      while i < count
        if launched[i] != 0
          thread = threads[i]
          if thread != nil && ffrpo_segment_finished(worker_binary, thread, launcher_states, i) != 0 && segment_joined[i] == 0
            joined = ffrpo_finish_segment(worker_binary, thread, launcher_states, i) ## i64
            threads[i] = nil
            segment_joined[i] = 1
            segment_ms = child_elapsed_ms[i] ## i64
            if segment_ms < 0
              segment_ms = 0
            total_wall_ms[i] += segment_ms
            body = read_file(child_status_paths[i])
            seg_rounds = shape_epoch_rounds ## i64
            if base_complete[i] != 0
              seg_rounds = 1
            if body != nil && body.size() > 0
              child_status_seen = ffrpo_parse_child_status(body, child_status_values) ## i64
              seq = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 0, 0) ## i64
              if seq > 0
                if base_complete[i] == 0
                  if seq < shape_epoch_rounds
                    seg_rounds = seq
                  if seq >= shape_epoch_rounds
                    seg_rounds = shape_epoch_rounds
                if base_complete[i] != 0
                  seg_rounds = 1
              acc_cpu_moves[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 1, 0)
              acc_gpu_moves[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 2, 0)
              acc_cpu_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 3, segment_ms * cpu_allocation[i])
              acc_gpu_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 4, 0)
              acc_mitm_attempts[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 5, 0)
              acc_mitm_pairs[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 6, 0)
              acc_mitm_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 7, 0)
              z = ffrpo_accumulate_parsed_accelerator_status(child_status_values, child_status_seen, i, acc_mitm_failures, acc_child_degraded) ## i64
              acc_gpu_failures[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 9, 0)
              acc_exact_rejects[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 11, 0)
              side_loaded[i] = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 12, side_loaded[i])
              side_seeded[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 13, 0)
              side_saved[i] = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 14, side_saved[i])
              side_rejects[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 15, 0)
              segment_side_failures = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 16, 0) ## i64
              side_write_failures[i] += segment_side_failures
              side_degraded[i] = 0
              if segment_side_failures > 0
                side_degraded[i] = 1
              if ffrpo_child_status_stopped(body) != 0
                terminal_rank = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 17, 0 - 1) ## i64
                terminal_bits = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 18, 0 - 1) ## i64
                if terminal_rank > 0 && terminal_bits >= 0
                  reported_ranks[i] = terminal_rank
                  reported_bits[i] = terminal_bits
                  reported_terminal[i] = 1
            if body != nil
              ccall("w_value_free", body)
            total_rounds[i] += seg_rounds
            if base_complete[i] == 0
              base_complete[i] = 1
              base_wall_ms[i] = segment_ms
          if base_complete[i] != 0
            finish = epoch_started_ms + base_wall_ms[i] ## i64
            if finish > deadline_ms
              deadline_ms = finish
          live_thread = threads[i]
          if base_complete[i] == 0 && live_thread != nil && ffrpo_segment_alive(worker_binary, live_thread, launcher_states, i) != 0
            live_body = read_file(child_status_paths[i])
            child_status_seen = ffrpo_parse_child_status(live_body, child_status_values) ## i64
            live_rounds = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 0, 0) ## i64
            predicted = ffrpo_predict_base_finish_ms(epoch_started_ms, now_ms, shape_epoch_rounds, live_rounds, 0, 0) ## i64
            if predicted > deadline_ms
              deadline_ms = predicted
            if live_body != nil
              ccall("w_value_free", live_body)
        i += 1

      now_ms = ccall("__w_clock_ms") ## i64
      i = 0
      while i < count
        do_fill = 1 ## i64
        if launched[i] == 0 || base_complete[i] == 0 || segment_joined[i] == 0
          do_fill = 0
        if exit_codes[i] != 0 || acc_exact_rejects[i] > 0 || stop_requested != 0
          do_fill = 0
        if ccall("__w_interrupted") != 0
          do_fill = 0
        avg_round = 0 ## i64
        if do_fill != 0 && total_rounds[i] > 0
          avg_round = total_wall_ms[i] / total_rounds[i]
        if do_fill != 0 && avg_round < 1 && total_wall_ms[i] > 0
          avg_round = total_wall_ms[i]
        if do_fill != 0 && ffrpo_should_fill_round(avg_round, now_ms, deadline_ms) == 0
          do_fill = 0
        if do_fill != 0
          fill_serial[i] += 1
          shape_label = labels[i]
          child_tag = ffrpo_child_tag(run_tag, shapes[i], epoch, fill_serial[i])
          remain_secs = child_max_secs ## i64
          if max_secs > 0
            remain_secs = max_secs - (now_ms - start_ms) / 1000
            if remain_secs < 1
              remain_secs = 1
          cleared = write_file(child_status_paths[i], "")
          if cleared
            child_elapsed_ms[i] = 0
            segment_joined[i] = 0
            restart_nonce = ffrcb_portfolio_nonce(epoch, i, fill_serial[i]) ## i64
            restart_door_ticket = ffrcb_portfolio_door_ticket(epoch, i, fill_serial[i]) ## i64
            threads[i] = ffrpo_dispatch_shape(worker_binary, launcher_threads, launcher_commands, launcher_states, shape_label, repo_root, best_paths[i], child_status_paths[i], child_tag, cpu_allocation[i], steps, 1, remain_secs, dslack, cycles, child_gpu_flags[i], gpu_allocation[i], gpu_steps, gpu_epoch_rounds, ffrpo_gpu_binary(gpu_binary, shape_label), 0, stop_on_record, 0, restart_nonce, restart_door_ticket, exit_codes, child_elapsed_ms, i)
            if threads[i] == nil
              exit_codes[i] = 2
              segment_joined[i] = 1
          if worker_binary != nil && worker_binary != ""
            ccall("w_value_free", child_tag)
        i += 1

      active_j = 0 ## i64
      active_gpu = 0 ## i64
      ready_count = ffrpp_ready_count(ready, count) ## i64
      i = 0
      while i < count
        thread = threads[i]
        active[i] = 0
        if thread != nil && ffrpo_segment_alive(worker_binary, thread, launcher_states, i) != 0
          active[i] = 1
          active_j += cpu_allocation[i]
          active_gpu += gpu_allocation[i]
        ages[i] = (now_ms - last_progress_ms[i]) / 1000
        i += 1

      render_due = 0 ## i64
      if tui != 0 && ff_tui_heartbeat_due(last_render_ms, now_ms, 200) == 1
        render_due = 1
      heartbeat_due = ff_tui_heartbeat_due(last_parent_status_ms, now_ms, 1000) ## i64
      if render_due != 0 || heartbeat_due != 0
        display_total_moves = total_moves ## i64
        display_child_degraded = status_degraded ## i64
        i = 0
        while i < count
          display_ranks[i] = ranks[i]
          display_bits[i] = bits[i]
          display_rank_drops[i] = rank_drops[i]
          display_density_gains[i] = density_gains[i]
          display_rewards[i] = rewards[i]
          display_shape_moves[i] = shape_moves[i] + acc_cpu_moves[i] + acc_gpu_moves[i]
          display_shape_cpu_moves[i] = shape_cpu_moves[i] + acc_cpu_moves[i]
          display_shape_gpu_moves[i] = shape_gpu_moves[i] + acc_gpu_moves[i]
          display_shape_mitm_attempts[i] = shape_mitm_attempts[i] + acc_mitm_attempts[i]
          display_shape_mitm_pairs[i] = shape_mitm_pairs[i] + acc_mitm_pairs[i]
          display_shape_mitm_ms[i] = shape_mitm_ms[i] + acc_mitm_ms[i]
          display_shape_mitm_failures[i] = shape_mitm_failures[i] + acc_mitm_failures[i]
          display_exposure[i] = exposure[i]
          display_cpu_failures[i] = failures[i]
          display_gpu_failures[i] = gpu_failures[i] + acc_gpu_failures[i]
          display_failures[i] = display_cpu_failures[i] + display_gpu_failures[i] + display_shape_mitm_failures[i]
          if acc_child_degraded[i] != 0
            display_child_degraded = 1
          display_ages[i] = ages[i]
          display_elapsed[i] = run_elapsed[i]
          if active[i] != 0
            display_elapsed[i] += (now_ms - epoch_started_ms) / 1000
          if active[i] == 0 && launched[i] != 0
            display_elapsed[i] += total_wall_ms[i] / 1000
          display_total_moves += acc_cpu_moves[i] + acc_gpu_moves[i]

          # Child status is cleared before each segment, so a non-empty body
          # belongs to the active segment of this epoch.
          # A joined child remains in the thread slot until it is replaced by
          # a fill segment. Its terminal status has already been accumulated
          # above, so only an unjoined segment contributes live counters here.
          if threads[i] != nil && segment_joined[i] == 0
            live_body = read_file(child_status_paths[i])
            if live_body != nil && live_body.size() > 0
              child_status_seen = ffrpo_parse_child_status(live_body, child_status_values) ## i64
              live_cpu_moves = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 1, 0) ## i64
              live_gpu_moves = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 2, 0) ## i64
              live_cpu_ms = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 3, 0) ## i64
              live_gpu_ms = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 4, 0) ## i64
              live_mitm_attempts = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 5, 0) ## i64
              live_mitm_pairs = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 6, 0) ## i64
              live_mitm_ms = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 7, 0) ## i64
              live_mitm_failures = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 8, 0) ## i64
              live_gpu_failures = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 9, 0) ## i64
              live_child_degraded = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 10, 0) ## i64
              live_rank = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 17, 0 - 1) ## i64
              live_bits = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 18, 0 - 1) ## i64
              display_total_moves += live_cpu_moves + live_gpu_moves
              display_shape_moves[i] += live_cpu_moves + live_gpu_moves
              display_shape_cpu_moves[i] += live_cpu_moves
              display_shape_gpu_moves[i] += live_gpu_moves
              display_shape_mitm_attempts[i] += live_mitm_attempts
              display_shape_mitm_pairs[i] += live_mitm_pairs
              display_shape_mitm_ms[i] += live_mitm_ms
              display_shape_mitm_failures[i] += live_mitm_failures
              live_cpu_quanta = (live_cpu_ms + 99) / 100 ## i64
              live_gpu_quanta = 0 ## i64
              if gpu_allocation[i] > 0 && live_gpu_ms > 0
                live_gpu_quanta = ((gpu_allocation[i] + 31) / 32) * ((live_gpu_ms + 99) / 100)
              display_exposure[i] += live_cpu_quanta + live_gpu_quanta + (acc_cpu_ms[i] + 99) / 100
              display_gpu_failures[i] += live_gpu_failures
              display_failures[i] = display_cpu_failures[i] + display_gpu_failures[i] + display_shape_mitm_failures[i]
              if live_mitm_failures > 0 || live_child_degraded > 0
                display_child_degraded = 1
              if live_rank > 0
                display_ranks[i] = live_rank
                if live_bits >= 0
                  display_bits[i] = live_bits
                if live_rank < ranks[i]
                  live_gain = ranks[i] - live_rank ## i64
                  display_rank_drops[i] += live_gain
                  display_rewards[i] += live_gain * 10000
                  display_ages[i] = 0
                if live_rank == ranks[i] && live_bits >= 0 && live_bits < bits[i]
                  live_bit_gain = bits[i] - live_bits ## i64
                  display_density_gains[i] += live_bit_gain
                  display_rewards[i] += live_bit_gain * 100
                  display_ages[i] = 0
            if live_body != nil
              ccall("w_value_free", live_body)
          i += 1

        degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, display_child_degraded)
        if heartbeat_due != 0
          sequence += 1
          live_status = ffrpo_status_body("running", sequence, epoch, elapsed_s, total_j, total_gpu_lanes, display_total_moves, degraded, labels, ready, cpu_allocation, gpu_allocation, display_ranks, display_bits, display_rank_drops, display_density_gains, display_shape_moves, display_shape_cpu_moves, display_shape_gpu_moves, display_shape_mitm_attempts, display_shape_mitm_pairs, display_shape_mitm_ms, display_shape_mitm_failures, display_exposure, display_cpu_failures, display_gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
          status_ok = ffrc_atomic_write(status_path, live_status, portfolio_write_tag, sequence)
          ccall("w_value_free", live_status)
          last_parent_status_ms = now_ms
          if status_ok == 0
            status_degraded = 1
          if status_ok != 0
            status_degraded = 0
          if status_degraded != 0
            display_child_degraded = 1
          degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, display_child_degraded)

      if render_due != 0
        last_render_ms = now_ms
        width = ccall("w_term_cols") ## i64
        if width < 1
          width = 70
        frame = ffrpo_frame_rows(labels, cpu_allocation, gpu_allocation, display_ranks, initial_ranks, display_bits, display_rank_drops, display_density_gains, display_rewards, display_exposure, display_failures, gpu_states, active, display_ages, display_elapsed, epoch, elapsed_s, total_j, active_j, total_gpu_lanes, active_gpu, display_total_moves, ready_count, degraded, flash_text, width)
        z = ffrpo_render_rows(frame)
      if tui != 0
        key = ccall("w_input_poll", 0) ## i64
        seen = 0 ## i64
        while key >= 0 && seen < 8
          if key == 32
            reset_requested = 1
            flash_text = "naive reset queued for the next exact epoch boundary"
          if key == 3 || key == 113 || key == 81
            stop_requested = 1
            flash_text = "stopping after the active rectangular epoch drains"
          seen += 1
          key = ccall("w_input_poll", 0)
      if ccall("__w_interrupted") != 0
        stop_requested = 1
        cancelled = ffrpo_cancel_active_segments(worker_binary, threads, launcher_threads, launcher_states, segment_joined, exit_codes, parent_cancelled) ## i64

      still = ffrpo_any_alive(threads, worker_binary, launcher_states) ## i64
      if still == 0
        # One more harvest/fill pass may have been needed after the last join.
        # Stop only when nothing is alive and no fill was just scheduled.
        pending_join = 0 ## i64
        i = 0
        while i < count
          if launched[i] != 0 && segment_joined[i] == 0
            pending_join = 1
          i += 1
        if pending_join == 0
          # Recompute deadline and see if any idle base-complete shape still fills.
          can_fill = 0 ## i64
          now2 = ccall("__w_clock_ms") ## i64
          dl = epoch_started_ms ## i64
          i = 0
          while i < count
            if launched[i] != 0 && base_complete[i] != 0
              finish = epoch_started_ms + base_wall_ms[i] ## i64
              if finish > dl
                dl = finish
            i += 1
          i = 0
          while i < count
            if launched[i] != 0 && base_complete[i] != 0 && segment_joined[i] != 0 && exit_codes[i] == 0 && acc_exact_rejects[i] == 0 && stop_requested == 0
              avg_round = 0 ## i64
              if total_rounds[i] > 0
                avg_round = total_wall_ms[i] / total_rounds[i]
              if ffrpo_should_fill_round(avg_round, now2, dl) != 0
                can_fill = 1
            i += 1
          if can_fill == 0
            epoch_running = 0
      # Once the last child has been harvested there is nothing left for the
      # poller to observe.  Avoid paying one unconditional 50 ms sleep at
      # every exact epoch boundary; live epochs retain the same poll cadence,
      # status cadence, fill decisions, and TUI heartbeat.
      if epoch_running != 0
        ccall("__w_sleep_ms", 50)

    i = 0
    while i < count
      thread = threads[i]
      # The live loop normally joins and harvests every completed segment.
      # Only a genuinely unharvested final segment belongs here; replaying an
      # already joined status doubles moves, reward exposure, and archive
      # counters.
      if thread != nil && segment_joined[i] == 0
        joined = ffrpo_finish_segment(worker_binary, thread, launcher_states, i) ## i64
        threads[i] = nil
        segment_joined[i] = 1
        if child_elapsed_ms[i] > 0 && launched[i] != 0
          # Final unharvested segment (should be rare after the loop).
          total_wall_ms[i] += child_elapsed_ms[i]
          body = read_file(child_status_paths[i])
          if body != nil && body.size() > 0
            child_status_seen = ffrpo_parse_child_status(body, child_status_values) ## i64
            acc_cpu_moves[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 1, 0)
            acc_gpu_moves[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 2, 0)
            acc_cpu_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 3, child_elapsed_ms[i] * cpu_allocation[i])
            acc_gpu_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 4, 0)
            acc_mitm_attempts[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 5, 0)
            acc_mitm_pairs[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 6, 0)
            acc_mitm_ms[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 7, 0)
            z = ffrpo_accumulate_parsed_accelerator_status(child_status_values, child_status_seen, i, acc_mitm_failures, acc_child_degraded) ## i64
            acc_gpu_failures[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 9, 0)
            acc_exact_rejects[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 11, 0)
            side_loaded[i] = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 12, side_loaded[i])
            side_seeded[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 13, 0)
            side_saved[i] = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 14, side_saved[i])
            side_rejects[i] += ffrpo_parsed_status_i64(child_status_values, child_status_seen, 15, 0)
            segment_side_failures = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 16, 0) ## i64
            side_write_failures[i] += segment_side_failures
            side_degraded[i] = 0
            if segment_side_failures > 0
              side_degraded[i] = 1
            if ffrpo_child_status_stopped(body) != 0
              terminal_rank = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 17, 0 - 1) ## i64
              terminal_bits = ffrpo_parsed_status_i64(child_status_values, child_status_seen, 18, 0 - 1) ## i64
              if terminal_rank > 0 && terminal_bits >= 0
                reported_ranks[i] = terminal_rank
                reported_bits[i] = terminal_bits
                reported_terminal[i] = 1
          if body != nil
            ccall("w_value_free", body)
          if base_complete[i] == 0
            base_complete[i] = 1
            base_wall_ms[i] = child_elapsed_ms[i]
            total_rounds[i] += shape_epoch_rounds
          if base_complete[i] != 0 && total_rounds[i] < shape_epoch_rounds
            total_rounds[i] = shape_epoch_rounds
      active[i] = 0
      i += 1

    now_ms = ccall("__w_clock_ms") ## i64
    elapsed_s = (now_ms - start_ms) / 1000
    record_hit = 0 ## i64
    i = 0
    while i < count
      if cpu_allocation[i] > 0 && ready[i] != 0
        cpu_moves_epoch = acc_cpu_moves[i] ## i64
        gpu_moves_epoch = acc_gpu_moves[i] ## i64
        mitm_attempts_epoch = acc_mitm_attempts[i] ## i64
        mitm_pairs_epoch = acc_mitm_pairs[i] ## i64
        mitm_ms_epoch = acc_mitm_ms[i] ## i64
        mitm_failures_epoch = acc_mitm_failures[i] ## i64
        cpu_ms_epoch = acc_cpu_ms[i] ## i64
        if cpu_ms_epoch < 1 && total_wall_ms[i] > 0
          cpu_ms_epoch = total_wall_ms[i] * cpu_allocation[i]
        gpu_ms_epoch = acc_gpu_ms[i] ## i64
        gpu_failure_epoch = acc_gpu_failures[i] ## i64
        exact_rejects_epoch = acc_exact_rejects[i] ## i64
        # `thread.kill` reports exit code 2 for a lease that this parent
        # intentionally cancelled while handling TERM/INT/HUP.  Do not turn
        # that synthetic code into a cumulative lease failure.  All genuine
        # child exits still take the normal fail-closed path, and the durable
        # checkpoint is exact-audited below even for a cancelled lease.
        failed = ffrpo_segment_precheck_failed(launched[i], exit_codes[i], exact_rejects_epoch, total_wall_ms[i], acc_cpu_moves[i], parent_cancelled[i]) ## i64
        if failed == 0
          checkpoint_size = file_size(best_paths[i])
          if checkpoint_size == nil || checkpoint_size < 1
            failed = 1
        if failed == 0
          audit_due = ffrpo_metric_audit_due(epoch) ## i64
          terminal_ok = reported_terminal[i] ## i64
          if terminal_ok != 0 && (reported_ranks[i] < 1 || reported_bits[i] < 0)
            terminal_ok = 0
          if audit_due == 0 && terminal_ok != 0
            metrics[i * 2] = reported_ranks[i]
            metrics[i * 2 + 1] = reported_bits[i]
          if audit_due != 0 || terminal_ok == 0
            new_metrics = ffrpo_load_metrics_reuse(labels[i], repo_root, best_paths[i], 0, metric_states[i], metrics, i * 2) ## i64
            if new_metrics == 0
              failed = 1
            if new_metrics != 0 && terminal_ok != 0
              if metrics[i * 2] != reported_ranks[i] || metrics[i * 2 + 1] != reported_bits[i]
                failed = 1
        if failed != 0
          failures[i] += 1
          retry_epoch[i] = epoch + ffrpo_backoff(failures[i]) + 1
          hard_degraded[i] = 1
          ready[i] = 0
        # These are operational counters, not reward counters: work performed
        # by a child remains real even if its exit/checkpoint/exact gate later
        # fails. Commit it once after every harvested epoch so a live status
        # cannot move backwards when that child becomes terminal.
        committed_moves = ffrpo_commit_operational(shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, i, cpu_moves_epoch, gpu_moves_epoch, mitm_attempts_epoch, mitm_pairs_epoch, mitm_ms_epoch, mitm_failures_epoch, failed) ## i64
        shape_moves[i] += committed_moves
        total_moves += committed_moves
        # Cal2zone and MITM failures remain monotone even when a later parent
        # checkpoint/exact gate fails. Only cal2zone failures affect its
        # scheduler backoff; MITM failure is tracked independently.
        if gpu_allocation[i] > 0
          if gpu_failure_epoch > 0
            gpu_failures[i] += gpu_failure_epoch
            gpu_retry_epoch[i] = epoch + ffrpo_backoff(gpu_failures[i]) + 1
            gpu_sched_ready[i] = 0
            gpu_states[i] = 0
          gpu_degraded[i] = ffrpo_accelerator_degraded_after_epoch(gpu_degraded[i], 1, gpu_failure_epoch, acc_child_degraded[i])
        if failed == 0
          hard_degraded[i] = 0
          cpu_quanta = (cpu_ms_epoch + 99) / 100 ## i64
          gpu_quanta = 0 ## i64
          if gpu_allocation[i] > 0 && gpu_ms_epoch > 0
            gpu_quanta = ((gpu_allocation[i] + 31) / 32) * ((gpu_ms_epoch + 99) / 100)
          exposure[i] += cpu_quanta + gpu_quanta
          run_elapsed[i] += total_wall_ms[i] / 1000
          old_rank = ranks[i] ## i64
          old_bits = bits[i] ## i64
          new_rank = metrics[i * 2] ## i64
          new_bits = metrics[i * 2 + 1] ## i64
          if reset_children[i] != 0
            reset_pending[i] = 0
          if new_rank < old_rank
            gain = old_rank - new_rank ## i64
            rank_drops[i] += gain
            rewards[i] += gain * 10000
            last_progress_ms[i] = now_ms
          if new_rank == old_rank && new_bits < old_bits
            bit_gain = old_bits - new_bits ## i64
            density_gains[i] += bit_gain
            rewards[i] += bit_gain * 100
            last_progress_ms[i] = now_ms
          ranks[i] = new_rank
          bits[i] = new_bits
          retry_epoch[i] = epoch + 1
          record = ffrp_record_rank(ffrp_n(labels[i]), ffrp_m(labels[i]), ffrp_p(labels[i])) ## i64
          if record > 0 && new_rank < record
            record_hit = 1
      ages[i] = (now_ms - last_progress_ms[i]) / 1000
      i += 1

    if reset_requested != 0
      reset_next = 1
      reset_requested = 0
    sequence += 1
    degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, status_degraded)
    status = ffrpo_status_body("running", sequence, epoch, elapsed_s, total_j, total_gpu_lanes, total_moves, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, shape_moves, shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, exposure, failures, gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
    status_ok = ffrc_atomic_write(status_path, status, portfolio_write_tag, sequence)
    ccall("w_value_free", status)
    last_parent_status_ms = now_ms
    if status_ok == 0
      status_degraded = 1
    if status_ok != 0
      status_degraded = 0
    degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, status_degraded)
    if quiet == 0 && tui == 0
      << ffrpp_report(epoch, shapes, ready, gpu_sched_ready, cpu_allocation, scores)
      i = 0
      while i < count
        combined_failures = failures[i] + gpu_failures[i] + shape_mitm_failures[i] ## i64
        << "RECT_PORTFOLIO_STATUS shape=" + labels[i] + " epoch=" + epoch.to_s() + " cpu=" + cpu_allocation[i].to_s() + " gpu=" + gpu_allocation[i].to_s() + " rank=" + ranks[i].to_s() + " bits=" + bits[i].to_s() + " moves=" + shape_moves[i].to_s() + " failures=" + combined_failures.to_s() + " cpu_failures=" + failures[i].to_s() + " gpu_failures=" + gpu_failures[i].to_s() + " mitm_failures=" + shape_mitm_failures[i].to_s()
        i += 1
      flush()

    epoch += 1
    if stop_requested != 0 || ccall("__w_interrupted") != 0
      running = 0
    if max_epochs > 0 && epoch >= max_epochs
      running = 0
    if max_secs > 0 && elapsed_s >= max_secs
      running = 0
    if stop_on_record != 0 && record_hit != 0
      running = 0
    if ffrpp_ready_count(ready, count) == 0 && running != 0
      ccall("__w_sleep_ms", 100)

  stopped_launchers = ffrpo_stop_process_launchers(worker_binary, launcher_threads, launcher_states) ## i64
  if tui != 0
    ccall("w_term_raw_disable")
    << ""
  final_ms = ccall("__w_clock_ms") ## i64
  final_elapsed_s = (final_ms - start_ms) / 1000 ## i64
  degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, side_degraded, status_degraded)
  final_status = ffrpo_status_body("stopped", sequence + 1, epoch, final_elapsed_s, total_j, total_gpu_lanes, total_moves, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, shape_moves, shape_cpu_moves, shape_gpu_moves, shape_mitm_attempts, shape_mitm_pairs, shape_mitm_ms, shape_mitm_failures, exposure, failures, gpu_failures, scores, side_loaded, side_seeded, side_saved, side_rejects, side_write_failures)
  z = ffrc_atomic_write(status_path, final_status, portfolio_write_tag, sequence + 1)
  ccall("w_value_free", final_status)
  ccall("w_value_free", portfolio_write_tag)
  result = "RECT_PORTFOLIO_RESULT epoch=" + epoch.to_s() + " elapsed=" + final_elapsed_s.to_s()
  i = 0
  while i < count
    result = result + " " + labels[i] + "=r" + ranks[i].to_s() + "/d" + bits[i].to_s()
    i += 1
  << result
  0
