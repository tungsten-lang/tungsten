# Stable presentation helpers for a multi-shape rectangular portfolio.
#
# This module deliberately contains no scheduling, terminal I/O, clocks, or
# tensor policy.  A coordinator takes one scalar telemetry snapshot per shape
# and can render the same rows whether the work came from the standalone
# rectangular campaign or from FlipFleet's square-tensor GPU pool.
#
# Snapshot fields (all i64):
#   0 allocation       lanes assigned to this shape (zero means inactive)
#   1 current_rank     live working rank, or <= 0 when unknown
#   2 best_rank        durable best rank, or <= 0 when unknown
#   3 density          best term density, or < 0 when unknown
#   4 progress         candidates/moves completed, or < 0 when unknown
#   5 reward_milli     accumulated milli-reward
#   6 reward_exposure  32-lane/100ms exposure quanta
#   7 gpu_capable      nonzero when a GPU worker exists for this shape
#   8 gpu_ready        nonzero when that worker is currently usable
#   9 gpu_active       nonzero while GPU work is in flight
#  10 idle_seconds     seconds since useful progress, or < 0 when unknown
#  11 epoch            completed scheduling epoch, or < 0 when unknown
#
# Rows are assembled and clipped while plain, then dimmed.  ANSI bytes can
# therefore never move a later field or alter the narrow-terminal clip point.

use flipfleet_tui

-> ffrpt_snapshot_size() i64
  12

-> ffrpt_snapshot(allocation, current_rank, best_rank, density, progress, reward_milli, reward_exposure, gpu_capable, gpu_ready, gpu_active, idle_seconds, epoch) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  status = i64[ffrpt_snapshot_size()]
  status[0] = allocation
  status[1] = current_rank
  status[2] = best_rank
  status[3] = density
  status[4] = progress
  status[5] = reward_milli
  status[6] = reward_exposure
  status[7] = gpu_capable
  status[8] = gpu_ready
  status[9] = gpu_active
  status[10] = idle_seconds
  status[11] = epoch
  status

-> ffrpt_snapshot_valid(status) (i64[]) i64
  if status.size() < ffrpt_snapshot_size()
    return 0
  1

-> ffrpt_snapshot_allocation(status) (i64[]) i64
  status[0]

-> ffrpt_snapshot_current_rank(status) (i64[]) i64
  status[1]

-> ffrpt_snapshot_best_rank(status) (i64[]) i64
  status[2]

-> ffrpt_snapshot_density(status) (i64[]) i64
  status[3]

-> ffrpt_snapshot_progress(status) (i64[]) i64
  status[4]

-> ffrpt_snapshot_reward_milli(status) (i64[]) i64
  status[5]

-> ffrpt_snapshot_reward_exposure(status) (i64[]) i64
  status[6]

-> ffrpt_snapshot_gpu_capable(status) (i64[]) i64
  status[7]

-> ffrpt_snapshot_gpu_ready(status) (i64[]) i64
  status[8]

-> ffrpt_snapshot_gpu_active(status) (i64[]) i64
  status[9]

-> ffrpt_snapshot_idle_seconds(status) (i64[]) i64
  status[10]

-> ffrpt_snapshot_epoch(status) (i64[]) i64
  status[11]

-> ffrpt_rank_pair(current_rank, best_rank) (i64 i64)
  current_text = "?"
  best_text = "?"
  if current_rank > 0
    current_text = current_rank.to_s()
  if best_rank > 0
    best_text = best_rank.to_s()
  "r" + current_text + "/r" + best_text

-> ffrpt_gpu_state(gpu_capable, gpu_ready, gpu_active) (i64 i64 i64)
  state = "cpu-only"
  if gpu_capable != 0
    state = "gpu blocked"
    if gpu_ready != 0
      state = "gpu idle"
      if gpu_active != 0
        state = "gpu active"
  state

# CPU-only shapes are active whenever they have an allocation.  GPU-capable
# shapes additionally need a ready worker with work in flight; allocated but
# between epochs is intentionally dim so the active set is visible at a glance.
-> ffrpt_is_active(allocation, gpu_capable, gpu_ready, gpu_active) (i64 i64 i64 i64) i64
  if allocation <= 0
    return 0
  if gpu_capable != 0
    if gpu_ready == 0 || gpu_active == 0
      return 0
  1

-> ffrpt_known_counter(label, value, field_width) (String i64 i64)
  text = label + "-"
  if value >= 0
    text = label + ff_tui_compact_fixed(value, 0)
  ff_tui_pad_right(text, field_width)

-> ffrpt_header_plain(width) (i64)
  row = ff_tui_pad_right("shape", 10)
  row = row + ff_tui_pad_left("alloc", 7) + "  "
  row = row + ff_tui_pad_right("current/best", 12)
  row = row + ff_tui_pad_right("density", 11)
  row = row + ff_tui_pad_right("progress", 13)
  row = row + ff_tui_pad_right("reward", 12)
  row = row + ff_tui_pad_right("engine", 14)
  row = row + ff_tui_pad_right("idle", 12)
  row = row + ff_tui_pad_right("epoch", 10)
  ff_tui_clip(row, width)

-> ffrpt_legend_plain(width) (i64)
  ff_tui_clip("progress=candidates/moves; reward=reward per 32-lane/100ms exposure", width)

# Fixed 103-column grid.  A smaller `width` clips its tail exactly like the
# existing CPU-island and GPU-role rows; a larger width does not add padding.
-> ffrpt_plain_row(shape, allocation, current_rank, best_rank, density, progress, reward_milli, reward_exposure, gpu_capable, gpu_ready, gpu_active, idle_seconds, epoch, width) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  rank_text = ffrpt_rank_pair(current_rank, best_rank)
  density_text = ffrpt_known_counter("den ", density, 11)
  progress_text = ffrpt_known_counter("prog ", progress, 13)

  reward_text = "rwd -"
  reward_per = ff_tui_gpu_reward_milli_per_lane_epoch(reward_milli, reward_exposure) ## i64
  if reward_per >= 0
    reward_text = "rwd " + ff_tui_fixed2_milli(reward_per)

  idle_text = "idle -"
  if idle_seconds >= 0
    idle_text = "idle " + ff_tui_duration(idle_seconds)

  epoch_text = "epoch -"
  if epoch >= 0
    epoch_text = "epoch " + ff_tui_compact_fixed(epoch, 0)

  allocation_text = allocation.to_s() + "l"
  row = ff_tui_pad_right(shape, 10)
  row = row + ff_tui_pad_left(allocation_text, 7) + "  "
  row = row + ff_tui_pad_right(rank_text, 12)
  row = row + density_text
  row = row + progress_text
  row = row + ff_tui_pad_right(reward_text, 12)
  row = row + ff_tui_pad_right(ffrpt_gpu_state(gpu_capable, gpu_ready, gpu_active), 14)
  row = row + ff_tui_pad_right(idle_text, 12)
  row = row + ff_tui_pad_right(epoch_text, 10)
  ff_tui_clip(row, width)

-> ffrpt_row(shape, allocation, current_rank, best_rank, density, progress, reward_milli, reward_exposure, gpu_capable, gpu_ready, gpu_active, idle_seconds, epoch, width) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  plain = ffrpt_plain_row(shape, allocation, current_rank, best_rank, density, progress, reward_milli, reward_exposure, gpu_capable, gpu_ready, gpu_active, idle_seconds, epoch, width)
  if ffrpt_is_active(allocation, gpu_capable, gpu_ready, gpu_active) != 0
    return plain
  ff_tui_dim(plain)

-> ffrpt_row_from_snapshot(shape, status, width) (String i64[] i64)
  if ffrpt_snapshot_valid(status) == 0
    return ffrpt_row(shape, 0, 0 - 1, 0 - 1, 0 - 1, 0 - 1, 0, 0, 0, 0, 0, 0 - 1, 0 - 1, width)
  ffrpt_row(shape, status[0], status[1], status[2], status[3], status[4], status[5], status[6], status[7], status[8], status[9], status[10], status[11], width)

# `shapes` and `statuses` are parallel arrays.  A missing snapshot is rendered
# as a zero-allocation dim row rather than crashing a partially initialized TUI.
-> ffrpt_portfolio_rows(shapes, statuses, width)
  rows = []
  rows.push(ff_tui_dim(ffrpt_header_plain(width)))
  i = 0 ## i64
  while i < shapes.size()
    if i < statuses.size()
      rows.push(ffrpt_row_from_snapshot(shapes[i], statuses[i], width))
    if i >= statuses.size()
      missing = ffrpt_snapshot(0, 0 - 1, 0 - 1, 0 - 1, 0 - 1, 0, 0, 0, 0, 0, 0 - 1, 0 - 1)
      rows.push(ffrpt_row_from_snapshot(shapes[i], missing, width))
    i += 1
  rows

# Ready-to-append dashboard section: the rule spans the terminal, while table
# content uses the same two-space indentation as the existing GPU portfolio.
-> ffrpt_section_rows(title, shapes, statuses, width)
  rows = []
  rows.push(ff_tui_rule(title, width))
  inner = width - 2 ## i64
  if inner < 0
    inner = 0
  body = ffrpt_portfolio_rows(shapes, statuses, inner)
  i = 0 ## i64
  while i < body.size()
    rows.push("  " + body[i])
    i += 1
  rows.push("  " + ff_tui_dim(ffrpt_legend_plain(inner)))
  rows

# ---- coordinator-facing rectangular campaign frame -------------------------
#
# A coordinator often already owns parallel scalar arrays and should not have
# to allocate packed snapshots merely to paint a frame.  This API accepts
# those arrays directly and intentionally does not depend on rectangular state
# objects.  `ready < 0` means the shape has no GPU implementation; zero means
# implemented but unavailable; nonzero means ready.  `score_milli` uses the
# same normalized units as the rest of the GPU dashboard.

-> ffrpt_array_i64(values, index, fallback) (i64[] i64 i64) i64
  if index >= 0 && index < values.size()
    return values[index]
  fallback

-> ffrpt_campaign_gpu_state(ready, active) (i64 i64)
  state = "cpu-only"
  if ready >= 0
    state = "gpu blocked"
    if ready != 0
      state = "gpu idle"
      if active != 0
        state = "gpu active"
  state

-> ffrpt_campaign_is_active(cpu_allocation, gpu_lanes, ready, active) (i64 i64 i64 i64) i64
  if active == 0
    return 0
  if cpu_allocation > 0
    return 1
  if gpu_lanes > 0 && ready != 0
    return 1
  0

-> ffrpt_campaign_header_plain(width) (i64)
  row = ff_tui_pad_right("shape", 10)
  row = row + ff_tui_pad_right("allocation", 14)
  row = row + ff_tui_pad_right("rank/start", 12)
  row = row + ff_tui_pad_right("bits", 11)
  row = row + ff_tui_pad_right("drops", 8)
  row = row + ff_tui_pad_right("gains", 8)
  row = row + ff_tui_pad_right("reward/exposure", 17)
  row = row + ff_tui_pad_right("failures", 9)
  row = row + ff_tui_pad_right("engine", 12)
  row = row + ff_tui_pad_right("age", 11)
  row = row + ff_tui_pad_right("elapsed", 11)
  ff_tui_clip(row, width)

-> ffrpt_campaign_legend_plain(width) (i64)
  ff_tui_clip("alloc: c=CPU workers, g=GPU lanes; reward/exposure; e=100ms CPU-thread or 32-GPU-lane quantum", width)

# Fixed 123-column scalar row used by ffrpt_frame_rows.  `rank` is the current
# durable best and `initial_rank` is the campaign's starting frontier.
-> ffrpt_campaign_plain_row(label, cpu_allocation, gpu_lanes, rank, initial_rank, bits, rank_drops, density_gains, score_milli, exposure, failures, ready, active, age_seconds, elapsed_seconds, width) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  allocation_text = ff_tui_compact_fixed(cpu_allocation, 0) + "c/" + ff_tui_compact_fixed(gpu_lanes, 0) + "g"
  rank_text = ffrpt_rank_pair(rank, initial_rank)

  bits_text = "bits -"
  if bits >= 0
    bits_text = "bits " + ff_tui_compact_fixed(bits, 0)

  drop_text = "drop-"
  if rank_drops >= 0
    drop_text = "drop" + ff_tui_compact_fixed(rank_drops, 0)

  gain_text = "gain-"
  if density_gains >= 0
    gain_text = "gain" + ff_tui_compact_fixed(density_gains, 0)

  score_text = "-/-e"
  score_per = ff_tui_gpu_reward_milli_per_lane_epoch(score_milli, exposure) ## i64
  if score_per >= 0
    score_text = ff_tui_fixed2_milli(score_per) + "/" + ff_tui_compact_fixed(exposure, 0) + "e"

  failure_text = "fail-"
  if failures >= 0
    failure_text = "fail" + ff_tui_compact_fixed(failures, 0)

  age_text = "age -"
  if age_seconds >= 0
    age_text = "age " + ff_tui_duration(age_seconds)

  elapsed_text = "run -"
  if elapsed_seconds >= 0
    elapsed_text = "run " + ff_tui_duration(elapsed_seconds)

  row = ff_tui_pad_right(label, 10)
  row = row + ff_tui_pad_right(allocation_text, 14)
  row = row + ff_tui_pad_right(rank_text, 12)
  row = row + ff_tui_pad_right(bits_text, 11)
  row = row + ff_tui_pad_right(drop_text, 8)
  row = row + ff_tui_pad_right(gain_text, 8)
  row = row + ff_tui_pad_right(score_text, 17)
  row = row + ff_tui_pad_right(failure_text, 9)
  gpu_active = 0 ## i64
  if gpu_lanes > 0 && active != 0
    gpu_active = 1
  row = row + ff_tui_pad_right(ffrpt_campaign_gpu_state(ready, gpu_active), 12)
  row = row + ff_tui_pad_right(age_text, 11)
  row = row + ff_tui_pad_right(elapsed_text, 11)
  ff_tui_clip(row, width)

-> ffrpt_campaign_row(label, cpu_allocation, gpu_lanes, rank, initial_rank, bits, rank_drops, density_gains, score_milli, exposure, failures, ready, active, age_seconds, elapsed_seconds, width) (String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  plain = ffrpt_campaign_plain_row(label, cpu_allocation, gpu_lanes, rank, initial_rank, bits, rank_drops, density_gains, score_milli, exposure, failures, ready, active, age_seconds, elapsed_seconds, width)
  if ffrpt_campaign_is_active(cpu_allocation, gpu_lanes, ready, active) != 0
    return plain
  ff_tui_dim(plain)

# Pure array-to-frame adapter for portfolio coordinators.  Labels determine
# row count; a short telemetry array gets an honest unknown/zero fallback.
-> ffrpt_frame_rows(title, labels, cpu_allocations, gpu_lanes, ranks, initial_ranks, bits, rank_drops, density_gains, scores_milli, exposures, failures, ready, active, ages_seconds, elapsed_seconds, width)
  rows = []
  rows.push(ff_tui_rule(title, width))
  inner = width - 2 ## i64
  if inner < 0
    inner = 0
  rows.push("  " + ff_tui_dim(ffrpt_campaign_header_plain(inner)))
  i = 0 ## i64
  while i < labels.size()
    cpu_allocation = ffrpt_array_i64(cpu_allocations, i, 0) ## i64
    gpu_allocation = ffrpt_array_i64(gpu_lanes, i, 0) ## i64
    rank = ffrpt_array_i64(ranks, i, 0 - 1) ## i64
    initial_rank = ffrpt_array_i64(initial_ranks, i, 0 - 1) ## i64
    density = ffrpt_array_i64(bits, i, 0 - 1) ## i64
    drops = ffrpt_array_i64(rank_drops, i, 0) ## i64
    gains = ffrpt_array_i64(density_gains, i, 0) ## i64
    score = ffrpt_array_i64(scores_milli, i, 0) ## i64
    exposure = ffrpt_array_i64(exposures, i, 0) ## i64
    failure_count = ffrpt_array_i64(failures, i, 0) ## i64
    is_ready = ffrpt_array_i64(ready, i, 0 - 1) ## i64
    is_active = ffrpt_array_i64(active, i, 0) ## i64
    age = ffrpt_array_i64(ages_seconds, i, 0 - 1) ## i64
    elapsed = ffrpt_array_i64(elapsed_seconds, i, 0 - 1) ## i64
    row = ffrpt_campaign_row(labels[i], cpu_allocation, gpu_allocation, rank, initial_rank, density, drops, gains, score, exposure, failure_count, is_ready, is_active, age, elapsed, inner)
    rows.push("  " + row)
    i += 1
  rows.push("  " + ff_tui_dim(ffrpt_campaign_legend_plain(inner)))
  rows
