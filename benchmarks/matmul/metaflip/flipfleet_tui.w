# flipfleet_tui.w -- pure native dashboard helpers for FlipFleet.
#
# This module owns presentation only: no terminal I/O, files, clocks, global
# state, or search policy.  A native coordinator can `use flipfleet_tui`, keep
# its own telemetry, and pass scalar snapshots or parallel history arrays to
# these functions.  Times used for health are monotonic milliseconds.  GPU
# rewards use integer milli-reward and 32-lane/100ms exposure quanta so
# normalization compares engines with very different epoch shapes.
#
# Public API families:
#   ff_tui_health, ff_tui_heartbeat_age_ms, ff_tui_heartbeat_due
#   ff_tui_objective, ff_tui_record_badge
#   ff_tui_cpu_island_row, ff_tui_gpu_role_row, ff_tui_rect_engine_row
#   ff_tui_frontier_diversity, ff_tui_shoulder_diversity
#   ff_tui_symmetry_diversity, ff_tui_gpu_pareto_diversity
#   ff_tui_cpu_effectiveness, ff_tui_gpu_effectiveness
#   ff_tui_timeline
#   ff_tui_paint, ff_tui_bold, ff_tui_dim, ff_tui_health_code
#   ff_tui_spark, ff_tui_rule, ff_tui_fit
#
# Sentinels: negative ages/distances mean unknown; nonpositive ranks mean
# unknown/absent.  Width-bounded row functions always return at most `width`
# ASCII bytes, which also makes them safe for a curses addnstr-style caller.
# Styling lives in a separate family: rows are built plain and clipped first,
# then painted, so SGR escapes never disturb the width accounting.

# ---- compact scalar formatting ------------------------------------------------

-> ff_tui_clip(text, width) (String i64)
  out = text
  if width <= 0
    out = ""
  if width > 0
    if text.size > width
      if width == 1
        out = "~"
      if width > 1
        out = text.slice(0, width - 1) + "~"
  out

-> ff_tui_pad_right(text, width) (String i64)
  out = ff_tui_clip(text, width)
  if out.size < width
    out = out + (" " * (width - out.size))
  out

-> ff_tui_pad_left(text, width) (String i64)
  out = ff_tui_clip(text, width)
  if out.size < width
    out = (" " * (width - out.size)) + out
  out

-> ff_tui_fixed2_hundredths(value) (i64)
  sign = ""
  n = value ## i64
  if n < 0
    sign = "-"
    n = 0 - n
  whole = n / 100 ## i64
  fraction = n % 100 ## i64
  frac = fraction.to_s
  if fraction < 10
    frac = "0" + frac
  sign + whole.to_s + "." + frac

-> ff_tui_fixed2_milli(value) (i64)
  sign = 1 ## i64
  n = value ## i64
  if n < 0
    sign = 0 - 1
    n = 0 - n
  # Nearest hundredth from a value expressed in thousandths.
  hundredths = (n + 5) / 10 ## i64
  ff_tui_fixed2_hundredths(hundredths * sign)

-> ff_tui_scaled1(value, divisor, suffix) (i64 i64 String)
  sign = ""
  n = value ## i64
  if n < 0
    sign = "-"
    n = 0 - n
  whole = n / divisor ## i64
  tenth = ((n % divisor) * 10) / divisor ## i64
  out = sign + whole.to_s
  if tenth != 0
    out = out + "." + tenth.to_s
  out + suffix

-> ff_tui_compact(value) (i64)
  n = value ## i64
  a = n ## i64
  if a < 0
    a = 0 - a
  out = n.to_s
  if a >= 1000
    out = ff_tui_scaled1(n, 1000, "K")
  if a >= 1000000
    out = ff_tui_scaled1(n, 1000000, "M")
  if a >= 1000000000
    out = ff_tui_scaled1(n, 1000000000, "B")
  if a >= 1000000000000
    out = ff_tui_scaled1(n, 1000000000000, "T")
  if a >= 1000000000000000
    out = ff_tui_scaled1(n, 1000000000000000, "P")
  out

# Like ff_tui_scaled1 but the tenth digit is always emitted ("10.0B", never
# "10B"), so a live counter keeps a constant width instead of jiggling as the
# decimal comes and goes.
-> ff_tui_scaled1_fixed(value, divisor, suffix) (i64 i64 String)
  sign = ""
  n = value ## i64
  if n < 0
    sign = "-"
    n = 0 - n
  whole = n / divisor ## i64
  tenth = ((n % divisor) * 10) / divisor ## i64
  sign + whole.to_s + "." + tenth.to_s + suffix

-> ff_tui_compact_fixed(value, width) (i64 i64)
  n = value ## i64
  a = n ## i64
  if a < 0
    a = 0 - a
  out = n.to_s
  if a >= 1000
    out = ff_tui_scaled1_fixed(n, 1000, "K")
  if a >= 1000000
    out = ff_tui_scaled1_fixed(n, 1000000, "M")
  if a >= 1000000000
    out = ff_tui_scaled1_fixed(n, 1000000000, "B")
  if a >= 1000000000000
    out = ff_tui_scaled1_fixed(n, 1000000000000, "T")
  if a >= 1000000000000000
    out = ff_tui_scaled1_fixed(n, 1000000000000000, "P")
  if width > 0
    out = ff_tui_pad_left(out, width)
  out

-> ff_tui_rate(rate_mps) (i64)
  out = "-"
  if rate_mps >= 0
    out = ff_tui_compact_fixed(rate_mps, 0) + "/s"
  out

-> ff_tui_duration(seconds) (i64)
  out = "-"
  if seconds >= 0
    if seconds < 60
      out = seconds.to_s + "s"
    if seconds >= 60
      minutes = seconds / 60 ## i64
      sec = seconds % 60 ## i64
      sec_s = sec.to_s
      if sec < 10
        sec_s = "0" + sec_s
      out = minutes.to_s + "m" + sec_s + "s"
    if seconds >= 3600
      hours = seconds / 3600 ## i64
      minute = (seconds % 3600) / 60 ## i64
      minute_s = minute.to_s
      if minute < 10
        minute_s = "0" + minute_s
      out = hours.to_s + "h" + minute_s + "m"
    if seconds >= 86400
      days = seconds / 86400 ## i64
      hour = (seconds % 86400) / 3600 ## i64
      hour_s = hour.to_s
      if hour < 10
        hour_s = "0" + hour_s
      out = days.to_s + "d" + hour_s + "h"
  out

-> ff_tui_duration_ms(milliseconds) (i64)
  out = "-"
  if milliseconds >= 0
    if milliseconds < 1000
      out = milliseconds.to_s + "ms"
    if milliseconds >= 1000
      out = ff_tui_duration(milliseconds / 1000)
  out

# ---- ANSI styling --------------------------------------------------------------
# Paint AFTER clipping: SGR escapes add bytes but zero display columns, so a
# painted pre-clipped row still occupies at most `width` terminal cells.

-> ff_tui_paint(text, code) (String String)
  out = text
  if code != ""
    out = "\e[" + code + "m" + text + "\e[0m"
  out

-> ff_tui_bold(text) (String)
  ff_tui_paint(text, "1")

-> ff_tui_dim(text) (String)
  ff_tui_paint(text, "2")

-> ff_tui_health_code(state) (String)
  code = "32"
  if state == "DEGRADED"
    code = "33"
  if state == "STALE"
    code = "31"
  if state == "COMPILING"
    code = "36"
  if state == "DONE"
    code = "1;32"
  if state == "FAILED"
    code = "1;31"
  code

# Prefer the painted composition when its plain twin fits; fall back to the
# clipped plain text in a terminal too narrow for the decorated line.
-> ff_tui_fit(plain, painted, width) (String String i64)
  out = painted
  if plain.size > width
    out = ff_tui_clip(plain, width)
  out

# Segment-wise fit: emit painted segments while their plain twins still fit
# `width`, then stop, so a narrow terminal drops trailing detail instead of
# losing color on the whole line.  Segment 0 always renders (clipped plain if
# even it is too wide).  Both arrays must be parallel and ASCII-measured.
-> ff_tui_join_fit(plains, painteds, width)
  first = plains[0]
  if first.size > width
    return ff_tui_clip(first, width)
  out = painteds[0]
  used = first.size ## i64
  full = 0 ## i64
  i = 1 ## i64
  while i < plains.size
    if full == 0
      seg = plains[i]
      fits = 0 ## i64
      if used + seg.size <= width
        fits = 1
      if fits == 1
        out = out + painteds[i]
        used += seg.size
      if fits == 0
        full = 1
    i += 1
  out

# ---- sparkline -----------------------------------------------------------------
# Last `width` values of an i64 series as block glyphs; a value at `lo` draws
# the shortest bar, so a descending rank series visibly shrinks left-to-right.
# Returns at most `width` display columns (the glyphs are multi-byte UTF-8).

-> ff_tui_spark(values, count, lo, hi, width) (i64[] i64 i64 i64 i64)
  blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  out = ""
  n = count ## i64
  if n > values.size
    n = values.size
  if width > 0
    if n > 0
      span = hi - lo ## i64
      if span < 1
        span = 1
      start = 0 ## i64
      if n > width
        start = n - width
      i = start ## i64
      while i < n
        idx = ((values[i] - lo) * 7) / span ## i64
        if idx < 0
          idx = 0
        if idx > 7
          idx = 7
        out = out + blocks[idx]
        i += 1
  out

# Pseudo-proportional sparkline over run-length levels: `levels`/`ticks` are
# parallel arrays of distinct values and how many render ticks each was held.
# Each level draws 1 glyph when brief, 2 when sustained, 3 when long-lived —
# so a quick drop stays one char and a plateau never flattens the story.
# When the runs exceed `width`, the oldest levels are dropped.

-> ff_tui_spark_runs(levels, ticks, level_count, width) (i64[] i64[] i64 i64)
  blocks = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
  out = ""
  n = level_count ## i64
  if n > levels.size
    n = levels.size
  if n > ticks.size
    n = ticks.size
  if n > 0
    if width > 0
      lo = levels[0] ## i64
      hi = levels[0] ## i64
      i = 1 ## i64
      while i < n
        if levels[i] < lo
          lo = levels[i]
        if levels[i] > hi
          hi = levels[i]
        i += 1
      span = hi - lo ## i64
      if span < 1
        span = 1
      segments = []
      budget = width ## i64
      i = n - 1
      while i >= 0 && budget > 0
        reps = 1 ## i64
        if ticks[i] >= 10
          reps = 2
        if ticks[i] >= 100
          reps = 3
        if reps > budget
          reps = budget
        idx = ((levels[i] - lo) * 7) / span ## i64
        if idx < 0
          idx = 0
        if idx > 7
          idx = 7
        segment = ""
        r = 0 ## i64
        while r < reps
          segment = segment + blocks[idx]
          r += 1
        segments.push(segment)
        budget -= reps
        i -= 1
      j = segments.size - 1 ## i64
      while j >= 0
        out = out + segments[j]
        j -= 1
  out

# ---- section rule ---------------------------------------------------------------
# "── title ────────" filled to exactly `width` display columns (byte length may
# exceed `width` because the rule glyph is multi-byte UTF-8).

-> ff_tui_rule(title, width) (String i64)
  if width < 8
    return ff_tui_clip(title, width)
  t = ff_tui_clip(title, width - 6)
  rest = width - t.size - 4 ## i64
  if rest < 0
    rest = 0
  "── " + t + " " + ("─" * rest)

# ---- producer health and heartbeat -------------------------------------------

-> ff_tui_heartbeat_age_ms(updated_ms, now_ms) (i64 i64) i64
  age = 0 - 1 ## i64
  if updated_ms >= 0
    if now_ms >= updated_ms
      age = now_ms - updated_ms
    if now_ms < updated_ms
      age = 0
  age

-> ff_tui_heartbeat_due(last_write_ms, now_ms, interval_ms) (i64 i64 i64) i64
  due = 0 ## i64
  if last_write_ms < 0
    due = 1
  if interval_ms <= 0
    due = 1
  if last_write_ms >= 0
    if now_ms - last_write_ms >= interval_ms
      due = 1
  due

# Precedence is intentional and stable:
# FAILED > DONE > COMPILING > STALE > DEGRADED > LIVE.
-> ff_tui_health(failed, done, compiling, degraded, updated_ms, now_ms, stale_after_ms) (i64 i64 i64 i64 i64 i64 i64)
  age = ff_tui_heartbeat_age_ms(updated_ms, now_ms) ## i64
  state = "LIVE"
  if degraded != 0
    state = "DEGRADED"
  if age >= 0
    if stale_after_ms > 0
      if age > stale_after_ms
        state = "STALE"
  if compiling != 0
    state = "COMPILING"
  if done != 0
    state = "DONE"
  if failed != 0
    state = "FAILED"
  state

-> ff_tui_health_line(failed, done, compiling, degraded, updated_ms, now_ms, stale_after_ms) (i64 i64 i64 i64 i64 i64 i64)
  state = ff_tui_health(failed, done, compiling, degraded, updated_ms, now_ms, stale_after_ms)
  age = ff_tui_heartbeat_age_ms(updated_ms, now_ms) ## i64
  detail = state
  if age >= 0
    detail = detail + " status-age " + ff_tui_duration_ms(age)
  if age < 0
    detail = detail + " status-age ?"
  detail

# ---- honest rank objective ----------------------------------------------------

-> ff_tui_objective_compare(best_rank, target_rank, noun) (i64 i64 String)
  out = "best r" + best_rank.to_s
  gap = best_rank - target_rank ## i64
  if gap > 0
    out = gap.to_s + " above " + noun + " " + target_rank.to_s
  if gap == 0
    out = "matches " + noun + " " + target_rank.to_s
  if gap < 0
    out = "beats " + noun + " " + target_rank.to_s + " by " + (0 - gap).to_s
  out

# `known_record` is 1 for a published world-record comparison and 0 for a
# configured baseline (e.g. naive 7×7).  `recovered_rank <= 0` means no
# recovered frontier.
-> ff_tui_objective(best_rank, configured_target, known_record, recovered_rank) (i64 i64 i64 i64)
  noun = "configured baseline"
  if known_record != 0
    noun = "world record"
  out = "best unknown"
  if configured_target > 0
    if best_rank <= 0
      out = out + " / " + noun + " " + configured_target.to_s
    if best_rank > 0
      out = ff_tui_objective_compare(best_rank, configured_target, noun)
      if recovered_rank > 0
        if recovered_rank != configured_target
          out = out + " / " + ff_tui_objective_compare(best_rank, recovered_rank, "recovered frontier")
  if configured_target <= 0
    if best_rank > 0
      out = "best rank " + best_rank.to_s
  out

# Compact title badge: "WR 93" for a known published record, "target 343" for
# an explicit non-record baseline, empty when no target is configured.
-> ff_tui_record_badge(configured_target, known_record) (i64 i64)
  out = ""
  if configured_target > 0
    if known_record != 0
      out = "WR " + configured_target.to_s
    if known_record == 0
      out = "target " + configured_target.to_s
  out

# ---- CPU islands --------------------------------------------------------------

# A row is a fixed grid of padded ASCII columns so a stack of walkers reads
# as a table.  Identity-bearing fields sit first so clipping retains a
# walker's distinct door and zone. The rank column is always
# `rCURRENT/rBEST`, where `rank` is the island's lifetime best and
# `current_rank` is the live working rank. Negative age/rate and nonpositive
# optional ranks/budgets mean unavailable. `#NNNNN` is the live term-set
# digest and `dN` its distance from the fleet leader. A dead island replaces
# its rate column with !state, ahead of the clip horizon.
-> ff_tui_cpu_island_row(id, door, zone, fleet_best, rank, current_rank, band, basin_id, basin_distance, moves, rate_mps, progress_age_s, source, process_state, work_moves, wander_moves, width) (i64 String String i64 i64 i64 i64 i64 i64 i64 i64 i64 String String i64 i64 i64)
  id_text = "w"
  if id < 10
    id_text = id_text + "0"
  id_text = id_text + id.to_s

  rank_text = "r?/r?"
  if current_rank > 0 && rank > 0
    rank_text = "r" + current_rank.to_s + "/r" + rank.to_s
  if current_rank > 0 && rank <= 0
    rank_text = "r" + current_rank.to_s + "/r?"
  if current_rank <= 0 && rank > 0
    rank_text = "r?/r" + rank.to_s

  delta_text = ""
  if rank > 0
    if fleet_best > 0
      delta = rank - fleet_best ## i64
      if delta == 0
        delta_text = "=best"
      if delta > 0
        delta_text = "+" + delta.to_s
      if delta < 0
        delta_text = delta.to_s

  band_text = ""
  if band >= 0
    band_text = "b" + band.to_s

  rate_text = "mv " + ff_tui_compact(moves)
  if rate_mps >= 0
    rate_text = ff_tui_rate(rate_mps)
  if process_state != ""
    if process_state != "running"
      rate_text = "!" + process_state

  idle_text = ""
  if progress_age_s >= 0
    idle_text = "idle " + ff_tui_duration(progress_age_s)

  budget_text = ""
  if work_moves > 0
    if wander_moves > 0
      budget_text = "W" + ff_tui_compact(work_moves) + "/" + ff_tui_compact(wander_moves)

  basin_text = ""
  if basin_id >= 0
    short_id = basin_id % 100000 ## i64
    basin_id_text = short_id.to_s()
    while basin_id_text.size() < 5
      basin_id_text = "0" + basin_id_text
    basin_text = "#" + basin_id_text
  distance_text = ""
  if basin_distance >= 0
    distance_text = "d" + basin_distance.to_s()

  row = ff_tui_pad_right(id_text, 4) + ff_tui_pad_right(door, 9) + ff_tui_pad_right(zone, 10) + ff_tui_pad_right(rank_text, 10) + ff_tui_pad_right(delta_text, 6) + ff_tui_pad_right(band_text, 5) + ff_tui_pad_left(rate_text, 9) + "  " + ff_tui_pad_right(idle_text, 10) + " " + ff_tui_pad_right(budget_text, 12) + " " + ff_tui_pad_right(distance_text, 5) + basin_text

  source_text = source
  prefix = door + "/"
  if source.starts_with?(prefix)
    if source.size > prefix.size
      source_text = source.slice(prefix.size, source.size - prefix.size)
  if source_text != ""
    if source_text != door
      row = row + " src:" + source_text

  ff_tui_clip(row, width)

# ---- GPU portfolio ------------------------------------------------------------

-> ff_tui_gpu_reward_milli_per_lane_epoch(reward_milli, lane_epochs) (i64 i64) i64
  result = 0 - 1 ## i64
  if lane_epochs > 0
    result = reward_milli / lane_epochs
  result

-> ff_tui_gpu_effectiveness(reward_milli, lane_epochs) (i64 i64)
  per = ff_tui_gpu_reward_milli_per_lane_epoch(reward_milli, lane_epochs) ## i64
  out = "- reward/lane-100ms"
  if per >= 0
    out = ff_tui_fixed2_milli(per) + " reward/lane-100ms"
  out

# Padded grid, mirroring the CPU island table.  Identity (role, lanes, seed)
# first, then the outcomes that get watched (cand/P/drop/den), health flags
# ahead of the normalized reward, and the engine recipe last as a diagnostic.
-> ff_tui_gpu_role_row(role, lanes, seed_rank, recipe, candidates, pareto_admissions, rank_drops, density_improvements, reward_milli, lane_epochs, failures, retrying, width) (String i64 i64 String i64 i64 i64 i64 i64 i64 i64 i64 i64)
  seed = "r?"
  if seed_rank > 0
    seed = "r" + seed_rank.to_s
  row = ff_tui_pad_right(role, 9) + ff_tui_pad_left(lanes.to_s + "l", 6) + "  " + ff_tui_pad_right(seed, 5) + ff_tui_pad_right("cand " + ff_tui_compact(candidates), 10) + ff_tui_pad_right("P" + pareto_admissions.to_s, 4) + ff_tui_pad_right("drop" + rank_drops.to_s, 7) + ff_tui_pad_right("den" + density_improvements.to_s, 6)
  if failures > 0
    row = row + ff_tui_pad_right("fail" + failures.to_s, 7)
  if failures <= 0
    row = row + ff_tui_pad_right("", 7)
  if retrying != 0
    row = row + ff_tui_pad_right("retry", 6)
  if retrying == 0
    row = row + ff_tui_pad_right("", 6)
  row = row + ff_tui_gpu_effectiveness(reward_milli, lane_epochs)
  if recipe != ""
    row = row + "  " + recipe
  ff_tui_clip(row, width)

# Rectangular Metal relay row: the GPU role grid without the Pareto column.
# A first-class rectangular campaign has no novelty bank, so printing "P0"
# would advertise an archive that does not exist.
-> ff_tui_rect_engine_row(role, lanes, seed_rank, recipe, candidates, rank_drops, density_improvements, reward_milli, lane_epochs, failures, retrying, width) (String i64 i64 String i64 i64 i64 i64 i64 i64 i64 i64)
  seed = "r?"
  if seed_rank > 0
    seed = "r" + seed_rank.to_s
  row = ff_tui_pad_right(role, 9) + ff_tui_pad_left(lanes.to_s + "l", 6) + "  " + ff_tui_pad_right(seed, 5) + ff_tui_pad_right("cand " + ff_tui_compact(candidates), 10) + ff_tui_pad_right("drop" + rank_drops.to_s, 7) + ff_tui_pad_right("den" + density_improvements.to_s, 6)
  if failures > 0
    row = row + ff_tui_pad_right("fail" + failures.to_s, 7)
  if failures <= 0
    row = row + ff_tui_pad_right("", 7)
  if retrying != 0
    row = row + ff_tui_pad_right("retry", 6)
  if retrying == 0
    row = row + ff_tui_pad_right("", 6)
  row = row + ff_tui_gpu_effectiveness(reward_milli, lane_epochs)
  if recipe != ""
    row = row + "  " + recipe
  ff_tui_clip(row, width)

# Two-column pool legend.  The active kernel stays at normal intensity while
# every inactive/unavailable strategy uses the dashboard's existing dim style.
-> ff_tui_gpu_pool_cell(name, active, ready, width) (String i64 i64 i64)
  marker = "· "
  if active != 0 && ready != 0
    marker = "● "
  label = name
  if ready == 0
    label = label + " unavailable"
  # String.size is UTF-8 byte length, while both glyphs occupy one terminal
  # column.  Pad the ASCII body separately so the three-byte active marker and
  # two-byte inactive marker always consume the same two visible columns.
  body_width = width - 2 ## i64
  if body_width < 0
    body_width = 0
  plain = marker + ff_tui_pad_right(label, body_width)
  if active != 0 && ready != 0
    return plain
  ff_tui_dim(plain)

-> ff_tui_gpu_pool_pair(left_name, left_active, left_ready, right_name, right_active, right_ready, width) (String i64 i64 String i64 i64 i64)
  cell_width = (width - 4) / 2 ## i64
  if cell_width < 20
    cell_width = 20
  left = ff_tui_gpu_pool_cell(left_name, left_active, left_ready, cell_width)
  right = ""
  if right_name != ""
    right = ff_tui_gpu_pool_cell(right_name, right_active, right_ready, cell_width)
  "    " + left + right

# ---- diversity ---------------------------------------------------------------

-> ff_tui_known_i64(value) (i64)
  out = "-"
  if value >= 0
    out = value.to_s
  out

-> ff_tui_frontier_diversity(size, capacity, min_distance, evictions, rejections) (i64 i64 i64 i64 i64)
  "Frontier " + size.to_s + "/" + capacity.to_s + " dmin " + ff_tui_known_i64(min_distance) + " evict " + evictions.to_s + " reject " + rejections.to_s

-> ff_tui_shoulder_diversity(near1_size, near1_capacity, near1_min_distance, near2_size, near2_capacity, near2_min_distance, structural_rejections, novelty_rejections) (i64 i64 i64 i64 i64 i64 i64 i64)
  "+1 " + near1_size.to_s + "/" + near1_capacity.to_s + " d" + ff_tui_known_i64(near1_min_distance) + " / +2 " + near2_size.to_s + "/" + near2_capacity.to_s + " d" + ff_tui_known_i64(near2_min_distance) + " / structural-reject " + ff_tui_known_i64(structural_rejections) + " novelty-reject " + ff_tui_known_i64(novelty_rejections)

-> ff_tui_symmetry_diversity(size, cpu_uses, gpu_uses) (i64 i64 i64)
  "Symmetry " + size.to_s + " seeds CPU uses " + cpu_uses.to_s + " GPU launches " + gpu_uses.to_s

-> ff_tui_gpu_pareto_diversity(size, capacity, admissions, rejections, evictions) (i64 i64 i64 i64 i64)
  "GPU Pareto " + size.to_s + "/" + capacity.to_s + " admit " + admissions.to_s + " reject " + rejections.to_s + " evict " + evictions.to_s

# ---- exposure-normalized effectiveness ---------------------------------------

# Productive CPU outcomes are rank drops + density ties + near-bank admissions.
# The result is fixed to hundredths per billion moves and never labels launches
# or cycle-outs as search wins.
-> ff_tui_productive_hundredths_per_billion(rank_drops, tie_improvements, near_admissions, moves) (i64 i64 i64 i64) i64
  out = 0 - 1 ## i64
  if moves > 0
    productive = rank_drops + tie_improvements + near_admissions ## i64
    scaled_moves = moves ## i64
    while productive > 90000000
      productive = (productive + 5) / 10
      scaled_moves = (scaled_moves + 5) / 10
    if scaled_moves > 0
      out = (productive * 100000000000) / scaled_moves
  out

-> ff_tui_cpu_effectiveness(cohort, moves, rank_drops, tie_improvements, near_admissions, width) (String i64 i64 i64 i64 i64)
  scaled = ff_tui_productive_hundredths_per_billion(rank_drops, tie_improvements, near_admissions, moves) ## i64
  yield_text = "-"
  if scaled >= 0
    yield_text = ff_tui_fixed2_hundredths(scaled)
  row = ff_tui_pad_right("CPU " + cohort, 23) + ff_tui_pad_left(yield_text, 7) + " productive/B  " + ff_tui_pad_right("drop" + rank_drops.to_s, 7) + ff_tui_pad_right("tie" + tie_improvements.to_s, 6) + ff_tui_pad_right("near" + near_admissions.to_s, 7) + ff_tui_compact_fixed(moves, 6) + " moves"
  ff_tui_clip(row, width)

# ---- time-aware rank timeline -------------------------------------------------

# `times_s` and `ranks` are parallel event arrays.  X is proportional to wall
# time, not event number; the retained incumbent is drawn to `elapsed_s`, so a
# long no-improvement plateau remains visible.  The lowest numeric rank is row
# zero (visually up).  Repeated-rank density events use `*`; rank events use `o`.
# At most eight rank rows plus one time axis are returned.
-> ff_tui_timeline(times_s, ranks, event_count, elapsed_s, width) (i64[] i64[] i64 i64 i64)
  lines = []
  n = event_count ## i64
  if n > times_s.size
    n = times_s.size
  if n > ranks.size
    n = ranks.size
  if n < 0
    n = 0

  if width < 12
    lines.push(ff_tui_clip("timeline unavailable", width))
  if width >= 12
    if n == 0
      lines.push(ff_tui_clip("No performance events yet", width))
    if n > 0
      low_rank = ranks[0] ## i64
      high_rank = ranks[0] ## i64
      horizon = elapsed_s ## i64
      i = 0 ## i64
      while i < n
        if ranks[i] < low_rank
          low_rank = ranks[i]
        if ranks[i] > high_rank
          high_rank = ranks[i]
        if times_s[i] > horizon
          horizon = times_s[i]
        i += 1
      if horizon < 1
        horizon = 1

      height = high_rank - low_rank + 1 ## i64
      if height < 1
        height = 1
      if height > 8
        height = 8
      label_width = 5 ## i64
      plot_width = width - label_width - 2 ## i64
      if plot_width < 4
        plot_width = 4

      grid = i64[height * plot_width]
      gi = 0 ## i64
      while gi < height * plot_width
        grid[gi] = 32
        gi += 1

      prev_x = 0 ## i64
      prev_y = 0 ## i64
      prev_rank = 0 ## i64
      have_prev = 0 ## i64
      i = 0
      while i < n
        t = times_s[i] ## i64
        if t < 0
          t = 0
        if t > horizon
          t = horizon
        x = (t * (plot_width - 1)) / horizon ## i64
        y = 0 ## i64
        if high_rank != low_rank
          y = ((ranks[i] - low_rank) * (height - 1)) / (high_rank - low_rank)
        if y < 0
          y = 0
        if y >= height
          y = height - 1

        if have_prev == 1
          xx = prev_x + 1 ## i64
          while xx < x
            grid[prev_y * plot_width + xx] = 45
            xx += 1
          if y != prev_y
            lo_y = y ## i64
            hi_y = prev_y ## i64
            if lo_y > hi_y
              tmp_y = lo_y ## i64
              lo_y = hi_y
              hi_y = tmp_y
            yy = lo_y + 1 ## i64
            while yy < hi_y
              grid[yy * plot_width + x] = 124
              yy += 1
            grid[prev_y * plot_width + x] = 43

        marker = 111 ## i64
        if have_prev == 1
          if ranks[i] == prev_rank
            marker = 42
        grid[y * plot_width + x] = marker
        prev_x = x
        prev_y = y
        prev_rank = ranks[i]
        have_prev = 1
        i += 1

      xx = prev_x + 1
      while xx < plot_width - 1
        grid[prev_y * plot_width + xx] = 45
        xx += 1
      if prev_x < plot_width - 1
        grid[prev_y * plot_width + plot_width - 1] = 62

      row = 0 ## i64
      while row < height
        label_rank = low_rank ## i64
        if height > 1
          label_rank = low_rank + (row * (high_rank - low_rank)) / (height - 1)
        body = ""
        x = 0
        while x < plot_width
          body = body + grid[row * plot_width + x].chr
          x += 1
        label = ff_tui_pad_right("r" + label_rank.to_s, label_width)
        lines.push(ff_tui_clip(label + " |" + body, width))
        row += 1

      left = "0s"
      right = ff_tui_duration(horizon)
      gap = plot_width - left.size - right.size ## i64
      if gap < 1
        gap = 1
      axis = left + (" " * gap) + right
      lines.push(ff_tui_clip((" " * (label_width + 2)) + axis, width))
  lines
