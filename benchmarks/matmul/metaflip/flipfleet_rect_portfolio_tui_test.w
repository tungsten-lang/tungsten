use flipfleet_rect_portfolio_tui

failures = 0 ## i64

-> ffrptt_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

# Active GPU row: every requested field is present and the normalized reward
# uses the same 32-lane/100ms exposure convention as the rest of FlipFleet.
active = ffrpt_plain_row("3x3x4", 256, 30, 29, 287, 12500000, 9000, 10, 1, 1, 1, 3, 42, 160)
failures += ffrptt_expect("fixed base width", active.size() == 103)
failures += ffrptt_expect("shape and allocation", active.starts_with?("3x3x4") && active.include?("256l"))
failures += ffrptt_expect("current best pair", active.include?("r30/r29"))
failures += ffrptt_expect("density and progress", active.include?("den 287") && active.include?("prog 12.5M"))
failures += ffrptt_expect("normalized reward", active.include?("rwd 0.90"))
failures += ffrptt_expect("GPU active", active.include?("gpu active"))
failures += ffrptt_expect("idle and epoch", active.include?("idle 3s") && active.include?("epoch 42"))

# Large values and unknown sentinels retain the exact same grid.  In
# particular, changing counter widths cannot make density/reward/engine jiggle.
large = ffrpt_plain_row("20x23x32", 16384, 4495, 4494, 123456789, 987654321000, 1234567, 12, 1, 1, 1, 90061, 1234567, 160)
unknown = ffrpt_plain_row("4x5x6", 0, 0 - 1, 0 - 1, 0 - 1, 0 - 1, 0, 0, 0, 0, 0, 0 - 1, 0 - 1, 160)
failures += ffrptt_expect("large fixed base width", large.size() == 103 && unknown.size() == 103)
failures += ffrptt_expect("density column stable", active.index("den ") == large.index("den ") && active.index("den ") == unknown.index("den "))
failures += ffrptt_expect("progress column stable", active.index("prog ") == large.index("prog ") && active.index("prog ") == unknown.index("prog "))
failures += ffrptt_expect("reward column stable", active.index("rwd ") == large.index("rwd ") && active.index("rwd ") == unknown.index("rwd "))
failures += ffrptt_expect("engine column stable", active.index("gpu active") == large.index("gpu active"))
failures += ffrptt_expect("unknown sentinels", unknown.include?("r?/r?") && unknown.include?("den -") && unknown.include?("prog -") && unknown.include?("rwd -"))

# Capability and activity are independent: CPU-only allocated work is normal,
# while zero-allocation, blocked, and between-epoch GPU work is dim.
styled_active = ffrpt_row("3x3x4", 256, 30, 29, 287, 12, 1, 1, 1, 1, 1, 0, 1, 160)
styled_zero = ffrpt_row("3x3x4", 0, 30, 29, 287, 12, 1, 1, 1, 1, 1, 0, 1, 160)
styled_idle = ffrpt_row("3x3x4", 256, 30, 29, 287, 12, 1, 1, 1, 1, 0, 0, 1, 160)
styled_blocked = ffrpt_row("3x3x4", 256, 30, 29, 287, 12, 1, 1, 1, 0, 0, 0, 1, 160)
styled_cpu = ffrpt_row("4x5x6", 2, 90, 90, 1150, 12, 1, 1, 0, 0, 0, 0, 1, 160)
failures += ffrptt_expect("active row normal", !styled_active.starts_with?("\e[2m"))
failures += ffrptt_expect("zero allocation dim", styled_zero.starts_with?("\e[2m") && styled_zero.ends_with?("\e[0m"))
failures += ffrptt_expect("GPU idle dim", styled_idle.starts_with?("\e[2m") && styled_idle.include?("gpu idle"))
failures += ffrptt_expect("GPU blocked dim", styled_blocked.starts_with?("\e[2m") && styled_blocked.include?("gpu blocked"))
failures += ffrptt_expect("CPU-only allocated normal", !styled_cpu.starts_with?("\e[2m") && styled_cpu.include?("cpu-only"))

# Clip before styling: a narrow inactive row has exactly the requested plain
# payload width, then one pair of zero-width SGR wrappers.
narrow_plain = ffrpt_plain_row("very-long-rectangular-shape", 0, 30, 29, 287, 12, 1, 1, 1, 1, 0, 0, 1, 47)
narrow_dim = ffrpt_row("very-long-rectangular-shape", 0, 30, 29, 287, 12, 1, 1, 1, 1, 0, 0, 1, 47)
failures += ffrptt_expect("narrow plain clipped", narrow_plain.size() == 47 && narrow_plain.ends_with?("~"))
failures += ffrptt_expect("narrow styled wraps clipped payload", narrow_dim == "\e[2m" + narrow_plain + "\e[0m")

# Snapshot schema and multi-shape helper tolerate an uninitialized trailing
# shape.  Active and inactive rows can therefore coexist without alignment or
# startup crashes.
status = ffrpt_snapshot(256, 30, 29, 287, 12500000, 9000, 10, 1, 1, 1, 3, 42)
failures += ffrptt_expect("snapshot size", status.size() == ffrpt_snapshot_size() && ffrpt_snapshot_valid(status) == 1)
failures += ffrptt_expect("snapshot accessors", ffrpt_snapshot_allocation(status) == 256 && ffrpt_snapshot_current_rank(status) == 30 && ffrpt_snapshot_best_rank(status) == 29 && ffrpt_snapshot_density(status) == 287 && ffrpt_snapshot_progress(status) == 12500000 && ffrpt_snapshot_reward_milli(status) == 9000 && ffrpt_snapshot_reward_exposure(status) == 10 && ffrpt_snapshot_gpu_capable(status) == 1 && ffrpt_snapshot_gpu_ready(status) == 1 && ffrpt_snapshot_gpu_active(status) == 1 && ffrpt_snapshot_idle_seconds(status) == 3 && ffrpt_snapshot_epoch(status) == 42)
short_status = i64[3]
failures += ffrptt_expect("short snapshot invalid", ffrpt_snapshot_valid(short_status) == 0)
shapes = ["3x3x4", "3x4x4", "4x4x5"]
statuses = []
statuses.push(status)
statuses.push(ffrpt_snapshot(0, 39, 38, 503, 44, 0, 0, 1, 1, 0, 7, 9))
rows = ffrpt_portfolio_rows(shapes, statuses, 160)
failures += ffrptt_expect("portfolio row count", rows.size() == 4)
failures += ffrptt_expect("header dim", rows[0].starts_with?("\e[2m") && rows[0].include?("current/best"))
failures += ffrptt_expect("portfolio active normal", !rows[1].starts_with?("\e[2m") && rows[1].include?("3x3x4"))
failures += ffrptt_expect("portfolio inactive dim", rows[2].starts_with?("\e[2m") && rows[2].include?("3x4x4"))
failures += ffrptt_expect("missing snapshot dim", rows[3].starts_with?("\e[2m") && rows[3].include?("4x4x5") && rows[3].include?("r?/r?"))

section = ffrpt_section_rows("Rectangular portfolio", shapes, statuses, 120)
failures += ffrptt_expect("section framing", section.size() == 6 && section[0].include?("Rectangular portfolio") && section[1].starts_with?("  \e[2m"))
failures += ffrptt_expect("section legend", section[5].include?("32-lane/100ms"))

# Coordinator-facing frame takes only scalar arrays.  Its richer row keeps
# CPU/GPU allocation, start rank, outcomes, health, and timing in fixed fields.
cpu_allocations = i64[3]
gpu_lanes = i64[3]
ranks = i64[3]
initial_ranks = i64[3]
bits = i64[3]
drops = i64[3]
gains = i64[3]
scores = i64[3]
exposures = i64[3]
failure_counts = i64[3]
ready = i64[3]
activity = i64[3]
ages = i64[3]
elapsed = i64[3]
cpu_allocations[0] = 2
gpu_lanes[0] = 256
ranks[0] = 29
initial_ranks[0] = 30
bits[0] = 287
drops[0] = 1
gains[0] = 4
scores[0] = 9000
exposures[0] = 10
failure_counts[0] = 2
ready[0] = 1
activity[0] = 1
ages[0] = 3
elapsed[0] = 3720
cpu_allocations[1] = 0
gpu_lanes[1] = 0
ranks[1] = 38
initial_ranks[1] = 39
bits[1] = 503
ready[1] = 1
activity[1] = 0
ages[1] = 90
elapsed[1] = 3720
cpu_allocations[2] = 1
gpu_lanes[2] = 0
ranks[2] = 60
initial_ranks[2] = 60
bits[2] = 919
ready[2] = 0 - 1
activity[2] = 0
ages[2] = 5
elapsed[2] = 72
campaign_plain = ffrpt_campaign_plain_row("3x3x4", 2, 256, 29, 30, 287, 1, 4, 9000, 10, 2, 1, 1, 3, 3720, 160)
campaign_large = ffrpt_campaign_plain_row("20x23x32", 192, 16384, 4494, 4495, 123456789, 1234, 5678, 1234567, 12000, 123, 1, 1, 90061, 987654, 160)
failures += ffrptt_expect("campaign fixed width", campaign_plain.size() == 123 && campaign_large.size() == 123)
failures += ffrptt_expect("campaign allocations", campaign_plain.include?("2c/256g"))
failures += ffrptt_expect("campaign rank start", campaign_plain.include?("r29/r30"))
failures += ffrptt_expect("campaign outcomes", campaign_plain.include?("bits 287") && campaign_plain.include?("drop1") && campaign_plain.include?("gain4"))
failures += ffrptt_expect("campaign score exposure", campaign_plain.include?("0.90/10e"))
failures += ffrptt_expect("campaign health timing", campaign_plain.include?("fail2") && campaign_plain.include?("gpu active") && campaign_plain.include?("age 3s") && campaign_plain.include?("run 1h02m"))
failures += ffrptt_expect("campaign columns stable", campaign_plain.index("bits ") == campaign_large.index("bits ") && campaign_plain.index("drop") == campaign_large.index("drop") && campaign_plain.index("gain") == campaign_large.index("gain") && campaign_plain.index("gpu active") == campaign_large.index("gpu active"))

campaign_frame = ffrpt_frame_rows("Rectangular portfolio", shapes, cpu_allocations, gpu_lanes, ranks, initial_ranks, bits, drops, gains, scores, exposures, failure_counts, ready, activity, ages, elapsed, 160)
failures += ffrptt_expect("campaign frame row count", campaign_frame.size() == 6)
failures += ffrptt_expect("campaign frame header", campaign_frame[1].include?("rank/start") && campaign_frame[1].include?("reward/exposure"))
failures += ffrptt_expect("campaign GPU active normal", !campaign_frame[2].starts_with?("  \e[2m") && campaign_frame[2].include?("3x3x4"))
failures += ffrptt_expect("campaign zero allocation dim", campaign_frame[3].starts_with?("  \e[2m") && campaign_frame[3].include?("gpu idle"))
failures += ffrptt_expect("campaign finished CPU row dims", campaign_frame[4].starts_with?("  \e[2m") && campaign_frame[4].include?("cpu-only"))
failures += ffrptt_expect("campaign frame legend", campaign_frame[5].include?("c=CPU workers") && campaign_frame[5].include?("100ms CPU-thread"))

# A live CPU child on a GPU-capable shape is bright, but 0g must still say
# gpu idle rather than borrowing the CPU activity bit for its engine state.
cpu_only_live = ffrpt_campaign_row("3x3x4", 1, 0, 29, 29, 204, 0, 0, 0, 0, 0, 1, 1, 0, 1, 160)
failures += ffrptt_expect("CPU child does not fake GPU activity", !cpu_only_live.starts_with?("\e[2m") && cpu_only_live.include?("gpu idle"))

# Array mismatch is a startup condition, not a renderer crash.  An empty age
# array falls back to unknown while the remaining row stays usable.
empty = i64[0]
short_frame = ffrpt_frame_rows("Rectangular portfolio", ["3x3x4"], cpu_allocations, gpu_lanes, ranks, initial_ranks, bits, drops, gains, scores, exposures, failure_counts, ready, activity, empty, empty, 160)
failures += ffrptt_expect("campaign short arrays safe", short_frame.size() == 4 && short_frame[2].include?("age -") && short_frame[2].include?("run -"))

if failures > 0
  << "flipfleet_rect_portfolio_tui_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_rect_portfolio_tui_test: all checks passed"
