# Duration literal parser split out of lowering/literals.w to keep literals.w
# within its 1,300-line boundary (compiler/test/test_module_boundaries.sh).

-> parse_duration(raw, ctx, node)
  # Parse compact duration: 2h30m, 500ms, 1y2mo3d, etc.
  # Returns {mode: 0, ns: value} or {mode: 1, months: m, ms: ms}
  total_months = 0
  total_ms = 0
  total_ns = 0
  has_calendar = false
  has_ns = false

  pos = 0
  chars = raw.chars()
  while pos < chars.size()
    # Scan number
    num_str = ""
    while pos < chars.size() && (chars[pos] >= "0" && chars[pos] <= "9")
      num_str += chars[pos]
      pos += 1
    num = num_str.to_i()

    # Scan unit
    if pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "o"
      total_months += num
      has_calendar = true
      pos += 2
    elsif pos + 1 < chars.size() && chars[pos] == "m" && chars[pos + 1] == "s"
      total_ms += num
      pos += 2
    elsif pos + 1 < chars.size() && chars[pos] == "n" && chars[pos + 1] == "s"
      total_ns += num
      has_ns = true
      pos += 2
    elsif pos < chars.size() && chars[pos] == "y"
      total_months += num * 12
      has_calendar = true
      pos += 1
    elsif pos < chars.size() && chars[pos] == "w"
      total_ms += num * 7 * 24 * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "d"
      total_ms += num * 24 * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "h"
      total_ms += num * 3600 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "m"
      total_ms += num * 60 * 1000
      pos += 1
    elsif pos < chars.size() && chars[pos] == "s"
      total_ms += num * 1000
      pos += 1
    else
      raise compile_error_for_node(:E_LOWER_DURATION_INVALID_UNIT, "Invalid duration unit at position [pos] in '[raw]'", ctx[:source_path], node)

  # Decide mode
  if has_calendar || (!has_ns && total_ms > 0)
    # Mode 1: months + ms
    return {mode: 1, months: total_months, ms: total_ms}

  if has_ns || total_ns > 0
    # Mode 0: nanoseconds
    ns = total_ns + total_ms * 1000000
    return {mode: 0, ns: ns}

  # Pure ms without calendar → mode 1
  {mode: 1, months: 0, ms: total_ms}
