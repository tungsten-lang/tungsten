# Pure-Tungsten coordinator for first-class rectangular FlipFleet campaigns.
#
# This is deliberately separate from the square coordinator's hot path.  A
# rectangular `--tensor` dispatch enters here before square state allocation;
# square 3x3..7x7 runs therefore pay no lane, memory, or scheduling overhead.
# CPU islands keep independent states across epochs.  One island is rebased
# after a fleet-best adoption, leaving the other islands in their old basins.
# Profiles with a checked-in specialized Metal bundle run that engine beside
# the CPU islands; CPU-only profiles are an expected capability, not DEGRADED.
#
# Interactive runs render the same styled dashboard as square FlipFleet
# (flipfleet_tui.w helpers, identical frame protocol and keyboard controls);
# --no-tui keeps the machine-parseable RECT_STATUS/RECT_RESULT stream.

use metaflip_rect_worker
use flipfleet_rect_gpu_bundle
use flipfleet_tui

-> ffrc_better(rank, bits, best_rank, best_bits) (i64 i64 i64 i64) i64
  if rank < best_rank
    return 1
  if rank == best_rank && bits < best_bits
    return 1
  0

-> ffrc_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffrc_thread_join_release(thread)
  ccall("w_thread_join_release", thread)

-> ffrc_file_nonempty(path) (String) i64
  body = read_file(path)
  if body != nil && body.size() > 0
    return 1
  0

-> ffrc_atomic_write(path, body, run_tag, nonce) (String String String i64) i64
  tmp = path + ".tmp." + run_tag + "." + nonce.to_s()
  wrote = write_file(tmp, body)
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      return 1
  0

-> ffrc_dump_atomic(state, path, run_tag, nonce) (i64[] String String i64) i64
  tmp = path + ".tmp." + run_tag + "." + nonce.to_s()
  rank = ffr_dump_best(state, tmp) ## i64
  if rank > 0
    moved = ccall("__w_rename", tmp, path)
    if moved
      return rank
  0 - 1

# Clone through the rectangular initializer rather than ffw_reseed_from:
# square reseeding interprets state word 3 as one factor width, whereas a
# rectangular state packs n/m/p there.  This path also repeats the exhaustive
# rectangular reconstruction gate at every coordinator adoption.
-> ffrc_clone_exact(src, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64)
  rank = ffr_best_rank(src) ## i64
  if rank < 1 || ffr_verify_best_exact(src, n, m, p) != 1
    return nil
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_best(src, us, vs, ws) ## i64
  if exported != rank
    return nil
  dst = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(dst, us, vs, ws, rank, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank
    return nil
  dst

-> ffrc_spawn_cpu(state, focused, adaptive, wander, elapsed_ms, slot) (i64[] i64 i64 i64 i64[] i64)
  Thread.new ->
    t0 = ccall("__w_clock_ms") ## i64
    z = ffr_work(state, focused) ## i64
    z = ffr_walk(state, adaptive)
    z = ffr_wander(state, wander)
    elapsed_ms[slot] = ccall("__w_clock_ms") - t0
    true

-> ffrc_binary_fresh(binary, source, metal, glue) (String String String String) i64
  binary_mtime = file_mtime_ns(binary)
  source_mtime = file_mtime_ns(source)
  metal_mtime = file_mtime_ns(metal)
  glue_mtime = file_mtime_ns(glue)
  if binary_mtime == nil || source_mtime == nil || metal_mtime == nil || glue_mtime == nil
    return 0
  if binary_mtime < source_mtime || binary_mtime < metal_mtime || binary_mtime < glue_mtime
    return 0
  1

# Keep the Metal device, library, pipeline, and buffers alive for the default
# one-round scheduler epochs.  This is the same command/ack protocol used by
# square FlipFleet's generic and 7x7 component workers, with a private mailbox
# namespace for a first-class rectangular campaign.
-> ffrc_persistent_command_path(run_tag, tensor) (String String)
  "/tmp/flipfleet_rect_campaign_cmd_" + run_tag + "_" + tensor + ".txt"

-> ffrc_persistent_ack_path(run_tag, tensor) (String String)
  "/tmp/flipfleet_rect_campaign_ack_" + run_tag + "_" + tensor + ".txt"

-> ffrc_persistent_wait(ack_path, generation, state, timeout_ms, process) i64
  start = ccall("__w_clock_ms") ## i64
  while ccall("__w_clock_ms") - start < timeout_ms
    if ffpg_ack_matches(read_file(ack_path), generation, state) == 1
      return 1
    if process != nil && process.alive? == false
      return 0
    z = ccall("__w_sleep_ms", 10)
  0

# A timed-out persistent worker must not survive a rectangular campaign
# epoch. Killing the controller thread triggers the runtime's OS.system
# cancellation cleanup, which terminates and waitpid-reaps that exact process
# group; no process-name matching is involved.
-> ffrc_persistent_force_stop(processes, active, process_lanes) i64
  process = processes[0]
  if process != nil
    if process.alive?
      z = process.kill
    result = ffrc_thread_join_release(process)
  processes[0] = nil
  active[0] = 0
  process_lanes[0] = 0
  1

-> ffrc_persistent_dispatch(base_command, log_path, run_tag, tensor, requested_lanes, steps, reseed, margin, workq, wanderq, wthr, escapes, processes, active, generations, process_lanes) i64
  process = processes[0]
  if active[0] != 0 && process != nil && process.alive? == false
    result = ffrc_thread_join_release(process)
    processes[0] = nil
    active[0] = 0
    process_lanes[0] = 0
  if active[0] != 0 && process_lanes[0] != requested_lanes
    return 0
  command_path = ffrc_persistent_command_path(run_tag, tensor)
  ack_path = ffrc_persistent_ack_path(run_tag, tensor)
  if active[0] == 0
    prepared = ffpg_prepare_mailboxes(command_path, ack_path, run_tag + "-rect-start") ## i64
    if prepared == 0
      return 0
    worker_command = ffpg_launch_command(base_command, command_path, ack_path)
    worker_command = worker_command + " >> " + ffrc_shell_quote(log_path) + " 2>&1"
    process = Thread.new ->
      system(worker_command)
    processes[0] = process
    active[0] = 2
    process_lanes[0] = requested_lanes
    ready = ffrc_persistent_wait(ack_path, 0, "ready", 30000, process) ## i64
    if ready == 0
      z = ffrc_persistent_force_stop(processes, active, process_lanes)
      return 0
    active[0] = 1
  if active[0] == 2
    if ffpg_ack_matches(read_file(ack_path), 0, "ready") == 1
      active[0] = 1
    if active[0] == 2
      return 0
  generations[0] = generations[0] + 1
  generation = generations[0] ## i64
  body = ffpg_command(generation, 1, steps, reseed, margin, workq, wanderq, wthr, escapes)
  published = ffpg_publish(command_path, body, run_tag + "-rect-run-" + generation.to_s()) ## i64
  if published == 0
    return 0
  completed = ffrc_persistent_wait(ack_path, generation, "done", 120000, processes[0]) ## i64
  if completed == 0
    z = ffrc_persistent_force_stop(processes, active, process_lanes)
  completed

-> ffrc_persistent_stop(run_tag, tensor, processes, active, generations, process_lanes) i64
  if active[0] == 0
    return 1
  process = processes[0]
  generations[0] = generations[0] + 1
  generation = generations[0] ## i64
  command_path = ffrc_persistent_command_path(run_tag, tensor)
  ack_path = ffrc_persistent_ack_path(run_tag, tensor)
  body = ffpg_command(generation, 0, 1, 1, 0, 1, 1, 1, 1)
  published = ffpg_publish(command_path, body, run_tag + "-rect-stop") ## i64
  stopped = 0 ## i64
  if published == 1
    stopped = ffrc_persistent_wait(ack_path, generation, "stopped", 30000, process)
  if stopped == 1 && process != nil
    result = ffrc_thread_join_release(process)
    process = nil
  if process != nil && process.alive? == false
    result = ffrc_thread_join_release(process)
    process = nil
    stopped = 1
  if stopped == 0
    stopped = ffrc_persistent_force_stop(processes, active, process_lanes)
  if stopped != 0
    processes[0] = nil
    active[0] = 0
    process_lanes[0] = 0
  stopped

-> ffrc_status_body(state_name, sequence, tensor, record, record_known, best, cpu_lanes, cpu_moves, cpu_ms, gpu_requested, gpu_supported, gpu_ready, gpu_lanes, gpu_moves, gpu_ms, gpu_failures, exact_rejects, elapsed_s) (String i64 String i64 i64 i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64)
  best_rank = ffr_best_rank(best) ## i64
  wr_gap = 0 ## i64
  wr_status = "unknown"
  if record > 0 && best_rank > 0
    wr_gap = best_rank - record
    if wr_gap > 0
      wr_status = "above"
    if wr_gap == 0
      wr_status = "ties"
    if wr_gap < 0
      wr_status = "beats"
  body = "schema=1 mode=rect producer_state=" + state_name + " sequence=" + sequence.to_s()
  body = body + " tensor=" + tensor + " record=" + record.to_s() + " record_known=" + record_known.to_s()
  body = body + " target=" + (record - 1).to_s() + " best_rank=" + best_rank.to_s() + " best_bits=" + ffr_best_bits(best).to_s()
  body = body + " wr_gap=" + wr_gap.to_s() + " wr_status=" + wr_status
  body = body + " cpu_lanes=" + cpu_lanes.to_s() + " cpu_moves=" + cpu_moves.to_s() + " cpu_ms=" + cpu_ms.to_s()
  body = body + " gpu_requested=" + gpu_requested.to_s() + " gpu_supported=" + gpu_supported.to_s() + " gpu_ready=" + gpu_ready.to_s()
  body = body + " gpu_lanes=" + gpu_lanes.to_s() + " gpu_moves=" + gpu_moves.to_s() + " gpu_ms=" + gpu_ms.to_s()
  body = body + " gpu_failures=" + gpu_failures.to_s() + " exact_rejects=" + exact_rejects.to_s() + " elapsed=" + elapsed_s.to_s() + "\n"
  body

# ---- native dashboard (shared FlipFleet TUI) --------------------------------

# Append one render tick to a run-length level history: extend the last run
# when the value repeats, otherwise start a new run, dropping the oldest level
# once 256 are held.  Returns the new level count.
-> ffrc_level_push(levels, ticks, count, value) (i64[] i64[] i64 i64) i64
  n = count ## i64
  if n > 0 && levels[n - 1] == value
    ticks[n - 1] = ticks[n - 1] + 1
    return n
  if n == 256
    h = 1 ## i64
    while h < 256
      levels[h - 1] = levels[h]
      ticks[h - 1] = ticks[h]
      h += 1
    n = 255
  levels[n] = value
  ticks[n] = 1
  n + 1

# Append one adoption event to the wall-time rank timeline, dropping the
# oldest event once 256 are held.  Returns the new event count.
-> ffrc_timeline_push(times, ranks, count, t, rank) (i64[] i64[] i64 i64 i64) i64
  n = count ## i64
  if n < 256
    times[n] = t
    ranks[n] = rank
    return n + 1
  ti = 0 ## i64
  while ti < 255
    times[ti] = times[ti + 1]
    ranks[ti] = ranks[ti + 1]
    ti += 1
  times[255] = t
  ranks[255] = rank
  256

# Build the styled dashboard rows for a first-class rectangular campaign —
# the same layout family as the square coordinator's ffn_render: title and
# honest objective, rank/density sparklines, CPU island table, Metal relay
# row, exposure-normalized effectiveness, and the wall-time rank timeline.
# Pure row builder (no terminal I/O, no clock reads) so tests can assert on
# frame content.
-> ffrc_frame_rows(tensor, seed_door, walkers, round, elapsed_s, total_moves, record, record_known, best, states, island_rates, island_ages, island_sources, phase_moves, gpu_requested, gpu_supported, gpu_ready, gpu_lanes, gpu_seed_rank, gpu_candidates, gpu_rank_drops, gpu_density, gpu_reward_milli, gpu_exposure, gpu_wall_ms, gpu_failures, cpu_moves, cpu_drops, cpu_ties, timeline_times, timeline_ranks, timeline_count, timeline_elapsed_s, degraded, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests_count, tie_bests_count, exact_rejects, dslack, flash_text, flash_until_ms, width)
  inner = width - 2 ## i64
  rows = []
  state = ff_tui_health(0, 0, 0, degraded, last_status_ms, now_ms, 5000)
  age_ms = ff_tui_heartbeat_age_ms(last_status_ms, now_ms) ## i64
  age_text = "?"
  if age_ms >= 0
    age_text = ff_tui_duration_ms(age_ms)
  age_text = ff_tui_pad_left(age_text, 5)
  objective = ff_tui_objective(ffr_best_rank(best), record, record_known, 0)
  record_badge = ff_tui_record_badge(record, record_known)
  record_plain = ""
  record_paint = ""
  if record_badge != ""
    record_plain = "  " + record_badge
    if record_known != 0
      record_paint = "  " + ff_tui_paint(record_badge, "1;36")
    if record_known == 0
      record_paint = "  " + ff_tui_dim(record_badge)
  dims = tensor.replace("x", ",")
  title_plain = "  flipfleet  <" + dims + "> GF(2)" + record_plain + "   " + state + " age " + age_text + "   seq " + sequence.to_s()
  title_paint = "  " + ff_tui_paint("flipfleet", "1;33") + "  ⟨" + dims + "⟩ GF(2)" + record_paint + "   " + ff_tui_paint(state, ff_tui_health_code(state)) + ff_tui_dim(" age " + age_text + "   seq " + sequence.to_s())
  rows.push(ff_tui_fit(title_plain, title_paint, width))

  best_bits_text = ffr_best_bits(best).to_s()
  moves_text = ff_tui_compact_fixed(total_moves, 6)
  stat_plains = ["  " + objective, "   density " + best_bits_text, "   moves " + moves_text, "   elapsed " + ff_tui_duration(elapsed_s), "   islands " + walkers.to_s(), "   round " + round.to_s()]
  stat_painteds = ["  " + ff_tui_paint(objective, "1;32"), "   " + ff_tui_dim("density") + " " + best_bits_text, "   " + ff_tui_dim("moves") + " " + moves_text, "   " + ff_tui_dim("elapsed") + " " + ff_tui_duration(elapsed_s), "   " + ff_tui_dim("islands") + " " + walkers.to_s(), "   " + ff_tui_dim("round") + " " + round.to_s()]
  rows.push(ff_tui_join_fit(stat_plains, stat_painteds, width))

  if rank_level_count >= 1
    spark_w = width - 24 ## i64
    if spark_w < 16
      spark_w = 16
    if spark_w > 120
      spark_w = 120
    rows.push("  " + ff_tui_dim("rank    ") + ff_tui_paint(ff_tui_spark_runs(rank_levels, rank_ticks, rank_level_count, spark_w), "32") + ff_tui_dim(" " + rank_levels[0].to_s() + "→" + ffr_best_rank(best).to_s()))
    rows.push("  " + ff_tui_dim("density ") + ff_tui_paint(ff_tui_spark_runs(bits_levels, bits_ticks, bits_level_count, spark_w), "33") + ff_tui_dim(" " + bits_levels[0].to_s() + "→" + best_bits_text))

  counter_plains = ["  new-bests " + new_bests_count.to_s(), "   ties " + tie_bests_count.to_s(), "   exact-rejects " + exact_rejects.to_s(), "   density-slack " + dslack.to_s()]
  counter_painteds = ["  " + ff_tui_dim("new-bests") + " " + new_bests_count.to_s(), "   " + ff_tui_dim("ties") + " " + tie_bests_count.to_s(), "   " + ff_tui_dim("exact-rejects") + " " + exact_rejects.to_s(), "   " + ff_tui_dim("density-slack") + " " + dslack.to_s()]
  rows.push(ff_tui_join_fit(counter_plains, counter_painteds, width))
  if flash_text != ""
    if now_ms < flash_until_ms
      rows.push("  " + ff_tui_paint(ff_tui_clip(flash_text, inner), "1;33"))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("CPU islands (independent basins; one island rebases per adoption)", width), "36"))
  i = 0 ## i64
  while i < walkers
    island_row = ff_tui_cpu_island_row(i, seed_door, "3-phase", ffr_best_rank(best), ffr_best_rank(states[i]), ffr_current_rank(states[i]), ffw_band(states[i]), 0 - 1, 0 - 1, ffr_moves(states[i]), island_rates[i], island_ages[i], island_sources[i], "running", phase_moves[0], phase_moves[2], inner)
    island_code = ""
    if ffr_best_rank(states[i]) == ffr_best_rank(best)
      island_code = "32"
    if island_ages[i] > 300
      island_code = "33"
    rows.push("  " + ff_tui_paint(island_row, island_code))
    i += 1
  rows.push("")
  if gpu_requested == 0
    rows.push(ff_tui_paint(ff_tui_rule("CPU-only run (--no-gpu)", width), "35"))
    rows.push("  " + ff_tui_dim("Metal relay disabled; " + walkers.to_s() + " islands x " + ff_tui_compact(phase_moves[0] + phase_moves[1] + phase_moves[2]) + " moves per round"))
  if gpu_requested != 0 && gpu_supported == 0
    rows.push(ff_tui_paint(ff_tui_rule("CPU-only profile (no specialized Metal bundle)", width), "35"))
    rows.push("  " + ff_tui_dim("no checked-in cal2zone geometry for " + tensor + "; CPU islands carry the campaign"))
  if gpu_requested != 0 && gpu_supported != 0
    rows.push(ff_tui_paint(ff_tui_rule("GPU cal2zone rectangular relay", width), "35"))
    if gpu_ready == 0
      rows.push("  " + ff_tui_paint("cal2zone build failed — continuing on CPU islands (fail " + gpu_failures.to_s() + ")", "31"))
    if gpu_ready != 0
      recipe = "cal2zone@" + ff_tui_duration_ms(gpu_wall_ms)
      engine_row = ff_tui_rect_engine_row("cal2zone", gpu_lanes, gpu_seed_rank, recipe, gpu_candidates, gpu_rank_drops, gpu_density, gpu_reward_milli, gpu_exposure, gpu_failures, 0, inner)
      engine_code = ""
      if gpu_failures > 0
        engine_code = "33"
      rows.push("  " + ff_tui_paint(engine_row, engine_code))
  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Effectiveness (exposure-normalized)", width), "36"))
  rows.push("  " + ff_tui_cpu_effectiveness("islands/3-phase", cpu_moves, cpu_drops, cpu_ties, 0, inner))
  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Rank timeline (wall-time; lower rank is up; * density-only)", width), "36"))
  lines = ff_tui_timeline(timeline_times, timeline_ranks, timeline_count, timeline_elapsed_s, inner)
  i = 0
  while i < lines.size()
    line_code = "32"
    if i == lines.size() - 1
      line_code = "2"
    if lines.size() == 1
      line_code = "2"
    rows.push("  " + ff_tui_paint(lines[i], line_code))
    i += 1
  if timeline_count <= 1
    rows.push("  " + ff_tui_dim("no adoptions yet this run — a new best rank plots o, a density-only best plots *"))
  rows.push("")
  rows.push("  " + ff_tui_dim("rank → asymptotic exponent (want ↓) · density → base-case ops (want ↓) · space=reset naive · w=reseed anchor · q/Ctrl-C stops"))
  rows

# Paint one frame: home + erase-to-EOL per row + erase-below, inside a DEC
# 2026 synchronized update — the exact frame protocol the square dashboard
# uses, so both campaigns look and update identically.
-> ffrc_render(rows) i64
  frame = "\e[?2026h\e[H"
  i = 0 ## i64
  while i < rows.size()
    frame = frame + rows[i] + "\e[K\n"
    i += 1
  frame = frame + "\e[J\e[?2026l"
  << frame
  flush()
  1

# Run a rectangular campaign using the common FlipFleet CLI controls.  Return
# 0 on a clean bounded/interrupt stop and 2 for an invalid seed/checkpoint.
# naive_seed != 0 starts from the schoolbook (n*m*p-term) scheme instead of
# the checked-in rectangular record (same meaning as square --naive).
-> ffrc_run(tensor, repo_root, seed_path, best_path, status_path, run_tag, walkers, steps, max_rounds, max_secs, dslack, cycles, record_override, gpu_requested, gpu_walkers, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, quiet, tui, stop_on_record, naive_seed, portfolio_child) (String String String String String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64 i64 i64 i64 i64) i64
  n = ffrp_n(tensor) ## i64
  m = ffrp_m(tensor) ## i64
  p = ffrp_p(tensor) ## i64
  if ffr_supported(n, m, p) != 1
    << "RECT_ERROR code=tensor tensor=" + tensor
    return 2

  capacity = ffr_default_capacity(n, m, p) ## i64
  state_size = ffr_state_size(capacity) ## i64
  workq = ffrp_work_quota(steps) ## i64
  wanderq = ffrp_wander_quota(steps) ## i64
  record = ffrp_record_rank(n, m, p) ## i64
  record_known = 1 ## i64
  if record_override > 0
    record = record_override
    record_known = 0
  # naive_seed still reports against the published WR; it only skips loading
  # record scheme files into the campaign inventory.

  anchor = i64[state_size]
  anchor_rank = 0 - 1 ## i64
  canonical_seed = seed_path
  if naive_seed != 0
    anchor_rank = ffr_init_naive_cap(anchor, n, m, p, capacity, 81001, dslack, cycles, workq, wanderq)
    canonical_seed = "naive"
  if naive_seed == 0
    if canonical_seed == "" || canonical_seed == "record"
      canonical_seed = repo_root + "/" + ffrp_seed_rel(n, m, p)
    anchor_rank = ffr_load_scheme_cap(anchor, canonical_seed, n, m, p, capacity, 81001, dslack, cycles, workq, wanderq)
  if anchor_rank < 1
    << "RECT_ERROR code=seed tensor=" + tensor + " path=" + canonical_seed
    return 2

  best = ffrc_clone_exact(anchor, n, m, p, capacity, 81013, dslack, cycles, workq, wanderq)
  if best == nil
    << "RECT_ERROR code=seed-exact tensor=" + tensor + " path=" + canonical_seed
    return 2

  # Under --naive, ignore any prior checkpoint (would re-inject earlier or
  # published knowledge).  Still write a fresh checkpoint for this run's own
  # discoveries.
  if naive_seed == 0
    durable_body = read_file(best_path)
    if durable_body != nil
      durable = i64[state_size]
      durable_rank = ffr_load_scheme_cap(durable, best_path, n, m, p, capacity, 81017, dslack, cycles, workq, wanderq) ## i64
      if durable_rank < 1
        << "RECT_ERROR code=checkpoint tensor=" + tensor + " path=" + best_path
        return 2
      if ffrc_better(durable_rank, ffr_best_bits(durable), ffr_best_rank(best), ffr_best_bits(best)) == 1
        durable_clone = ffrc_clone_exact(durable, n, m, p, capacity, 81019, dslack, cycles, workq, wanderq)
        if durable_clone != nil
          best = durable_clone
  persisted = ffrc_dump_atomic(best, best_path, run_tag, 0) ## i64
  if persisted < 1
    << "RECT_ERROR code=checkpoint-write tensor=" + tensor + " path=" + best_path
    return 2

  states = []
  lane = 0 ## i64
  while lane < walkers
    island = ffrc_clone_exact(best, n, m, p, capacity, 82001 + lane * 97, dslack, cycles, workq, wanderq)
    if island == nil
      << "RECT_ERROR code=island-init tensor=" + tensor + " lane=" + lane.to_s()
      return 2
    states.push(island)
    lane += 1

  # Per-island dashboard telemetry: seed provenance, move rates, and the age
  # of each island's own last (rank,density) improvement.
  seed_door = "record"
  if naive_seed != 0
    seed_door = "naive"
  init_ms = ccall("__w_clock_ms") ## i64
  island_sources = []
  island_rates = i64[walkers]
  island_ages = i64[walkers]
  island_last_progress_ms = i64[walkers]
  island_last_rank = i64[walkers]
  island_last_bits = i64[walkers]
  island_last_moves = i64[walkers]
  lane = 0
  while lane < walkers
    island_sources.push(seed_door)
    island_last_progress_ms[lane] = init_ms
    island_last_rank[lane] = ffr_best_rank(states[lane])
    island_last_bits[lane] = ffr_best_bits(states[lane])
    island_last_moves[lane] = ffr_moves(states[lane])
    lane += 1

  gpu_supported = ffrgb_supported(n, m, p) ## i64
  gpu_ready = 0 ## i64
  gpu_failures = 0 ## i64
  lanes = ffrgb_round_lanes(n, m, p, gpu_walkers) ## i64
  if gpu_requested == 0
    lanes = 0
  if gpu_requested != 0 && gpu_supported == 0
    lanes = 0
    if quiet == 0
      << "RECT_CAPABILITY tensor=" + tensor + " cpu=1 gpu=0 reason=cpu-only-profile"
  if gpu_requested != 0 && gpu_supported != 0
    if gpu_binary == ""
      gpu_binary = "/tmp/flipfleet_rect_gpu_" + ffrgb_tag(n, m, p)
    source = ffrgb_source_path(repo_root, n, m, p)
    metal = ffrgb_metal_path(repo_root, n, m, p)
    glue = repo_root + "/benchmarks/matmul/metaflip/flipfleet_rect_gpu_bundle.w"
    needs_build = gpu_rebuild ## i64
    if needs_build == 0
      if ffrc_binary_fresh(gpu_binary, source, metal, glue) == 0 || ffrgb_metallib_fresh(repo_root, n, m, p, gpu_binary) == 0
        needs_build = 1
    if needs_build != 0
      if quiet == 0
        << "RECT_CAPABILITY tensor=" + tensor + " cpu=1 gpu=building engine=cal2zone lanes=" + lanes.to_s()
        flush()
      gpu_ready = ffrgb_build(repo_root, n, m, p, gpu_binary)
    if needs_build == 0
      gpu_ready = 1
    if gpu_ready == 0
      gpu_failures += 1
      lanes = 0
      << "RECT_ERROR code=gpu-build tensor=" + tensor + " fallback=cpu"
  if quiet == 0
    display = "status-lines"
    if tui != 0
      display = "tui"
    << "RECT_CAPABILITY tensor=" + tensor + " cpu=1 cpu_lanes=" + walkers.to_s() + " gpu_supported=" + gpu_supported.to_s() + " gpu_ready=" + gpu_ready.to_s() + " gpu_lanes=" + lanes.to_s() + " display=" + display
    flush()

  phase_moves = i64[3]
  z = ffrp_campaign_budgets(steps, phase_moves)
  elapsed_cpu = i64[walkers]
  cpu_moves = 0 ## i64
  cpu_ms = 0 ## i64
  gpu_moves = 0 ## i64
  gpu_ms = 0 ## i64
  exact_rejects = 0 ## i64
  sequence = 0 ## i64
  round = 0 ## i64
  running = 1 ## i64
  start_ms = ccall("__w_clock_ms") ## i64
  trap_ok = ccall("__w_trap_interrupts")

  # Dashboard state: adoption counters, run-length sparkline histories, the
  # wall-time rank timeline, and raw keyboard controls.  Raw mode clears ISIG,
  # so Ctrl-C arrives as byte 3 and is handled in the key loop between rounds.
  new_bests = 0 ## i64
  tie_bests = 0 ## i64
  cpu_drops = 0 ## i64
  cpu_ties = 0 ## i64
  gpu_seed_rank = 0 ## i64
  gpu_candidates = 0 ## i64
  gpu_rank_drops = 0 ## i64
  gpu_density_improvements = 0 ## i64
  gpu_reward_milli = 0 ## i64
  gpu_exposure = 0 ## i64
  timeline_times = i64[256]
  timeline_ranks = i64[256]
  timeline_count = 1 ## i64
  timeline_ranks[0] = ffr_best_rank(best)
  timeline_start_s = 0 ## i64
  rank_levels = i64[256]
  rank_ticks = i64[256]
  rank_level_count = 0 ## i64
  bits_levels = i64[256]
  bits_ticks = i64[256]
  bits_level_count = 0 ## i64
  flash_text = ""
  flash_until_ms = 0 ## i64
  last_render_ms = 0 - 1 ## i64
  last_status_ms = 0 - 1 ## i64
  status_degraded = 0 ## i64
  stop_key = 0 ## i64
  if tui != 0
    ccall("w_term_raw_enable")
  gpu_seed_path = "/tmp/flipfleet_rect_seed_" + run_tag + "_" + ffrgb_tag(n, m, p) + ".txt"
  gpu_output_path = "/tmp/flipfleet_rect_best_" + run_tag + "_" + ffrgb_tag(n, m, p) + ".txt"
  gpu_log_path = "/tmp/flipfleet_rect_log_" + run_tag + "_" + ffrgb_tag(n, m, p) + ".txt"
  persistent_processes = []
  persistent_processes.push(nil)
  persistent_active = i64[1]
  persistent_generations = i64[1]
  persistent_lanes = i64[1]

  while running == 1
    cpu_threads = []
    lane = 0
    while lane < walkers
      elapsed_cpu[lane] = 0
      cpu_threads.push(ffrc_spawn_cpu(states[lane], phase_moves[0], phase_moves[1], phase_moves[2], elapsed_cpu, lane))
      lane += 1

    gpu_thread = nil
    gpu_elapsed = i64[1]
    if gpu_ready != 0 && lanes > 0
      seeded = ffrc_dump_atomic(best, gpu_seed_path, run_tag, round + 1000) ## i64
      cleared = write_file(gpu_output_path, "")
      if seeded > 0 && cleared
        gpu_seed_rank = ffr_best_rank(best)
        command = ffrgb_epoch_command(repo_root, gpu_binary, n, m, p, gpu_seed_path, gpu_output_path, "", record - 1, gpu_steps, 200, dslack, workq, wanderq, 7, lanes, "", lanes, gpu_epoch_rounds)
        if command != ""
          gpu_thread = Thread.new ->
            t0 = ccall("__w_clock_ms") ## i64
            ok = false
            if gpu_epoch_rounds == 1
              persistent_ok = ffrc_persistent_dispatch(command, gpu_log_path, run_tag, tensor, lanes, gpu_steps, 200, dslack, workq, wanderq, 7, lanes, persistent_processes, persistent_active, persistent_generations, persistent_lanes) ## i64
              if persistent_ok == 1
                ok = true
            if gpu_epoch_rounds != 1
              bounded_command = command + " > " + ffrc_shell_quote(gpu_log_path) + " 2>&1"
              ok = system(bounded_command)
            gpu_elapsed[0] = ccall("__w_clock_ms") - t0
            ok
      if gpu_thread == nil
        gpu_failures += 1

    lane = 0
    while lane < cpu_threads.size()
      result = cpu_threads[lane].join
      lane += 1
    if gpu_thread != nil
      gpu_ok = gpu_thread.join
      if gpu_ok != true
        gpu_failures += 1
      gpu_ms += gpu_elapsed[0]
      gpu_moves += lanes * gpu_steps * gpu_epoch_rounds
      # Exposure in 32-lane/100ms quanta, the square dashboard's reward
      # normalization unit, so engine effectiveness reads on the same scale.
      lane_chunks = lanes / 32 ## i64
      if lane_chunks < 1
        lane_chunks = 1
      elapsed_quanta = (gpu_elapsed[0] + 99) / 100 ## i64
      if elapsed_quanta < 1
        elapsed_quanta = 1
      gpu_exposure += lane_chunks * elapsed_quanta

    now_ms = ccall("__w_clock_ms") ## i64
    elapsed_s = (now_ms - start_ms) / 1000 ## i64
    adopted = 0 ## i64
    lane = 0
    while lane < walkers
      cpu_ms += elapsed_cpu[lane]
      candidate = states[lane]
      moves_now = ffr_moves(candidate) ## i64
      delta_moves = moves_now - island_last_moves[lane] ## i64
      if delta_moves < 0
        delta_moves = moves_now
      island_last_moves[lane] = moves_now
      worker_ms = elapsed_cpu[lane] ## i64
      if worker_ms < 1
        worker_ms = 1
      island_rates[lane] = delta_moves * 1000 / worker_ms
      lane_rank = ffr_best_rank(candidate) ## i64
      lane_bits = ffr_best_bits(candidate) ## i64
      if ffrc_better(lane_rank, lane_bits, island_last_rank[lane], island_last_bits[lane]) == 1
        island_last_rank[lane] = lane_rank
        island_last_bits[lane] = lane_bits
        island_last_progress_ms[lane] = now_ms
      island_ages[lane] = (now_ms - island_last_progress_ms[lane]) / 1000
      if ffr_verify_best_exact(candidate, n, m, p) == 1
        candidate_rank = ffr_best_rank(candidate) ## i64
        candidate_bits = ffr_best_bits(candidate) ## i64
        if ffrc_better(candidate_rank, candidate_bits, ffr_best_rank(best), ffr_best_bits(best)) == 1
          clone = ffrc_clone_exact(candidate, n, m, p, capacity, 83003 + round * 131 + lane, dslack, cycles, workq, wanderq)
          if clone != nil
            if candidate_rank < ffr_best_rank(best)
              new_bests += 1
              cpu_drops += 1
            else
              tie_bests += 1
              cpu_ties += 1
            timeline_count = ffrc_timeline_push(timeline_times, timeline_ranks, timeline_count, elapsed_s - timeline_start_s, candidate_rank)
            best = clone
            adopted = 1
      else
        exact_rejects += 1
      lane += 1
    cpu_moves += walkers * steps

    if gpu_thread != nil && ffrc_file_nonempty(gpu_output_path) == 1
      gpu_candidate = i64[state_size]
      gpu_rank = ffr_load_scheme_cap(gpu_candidate, gpu_output_path, n, m, p, capacity, 84007 + round * 137, dslack, cycles, workq, wanderq) ## i64
      if gpu_rank > 0
        gpu_candidates += 1
        # Same milli-reward scale as the square GPU portfolio: rank gain
        # dominates, same-rank density gain is bounded at 2000.
        rank_gain = ffr_best_rank(best) - gpu_rank ## i64
        if rank_gain > 0
          gpu_rank_drops += 1
          gpu_reward_milli += rank_gain * 10000
        if rank_gain <= 0 && gpu_rank == ffr_best_rank(best)
          bit_gain = ffr_best_bits(best) - ffr_best_bits(gpu_candidate) ## i64
          if bit_gain > 0 && ffr_best_bits(best) > 0
            gpu_density_improvements += 1
            density_reward = (2000 * bit_gain) / ffr_best_bits(best) ## i64
            if density_reward > 2000
              density_reward = 2000
            gpu_reward_milli += density_reward
        if ffrc_better(gpu_rank, ffr_best_bits(gpu_candidate), ffr_best_rank(best), ffr_best_bits(best)) == 1
          gpu_clone = ffrc_clone_exact(gpu_candidate, n, m, p, capacity, 84011 + round * 139, dslack, cycles, workq, wanderq)
          if gpu_clone != nil
            if gpu_rank < ffr_best_rank(best)
              new_bests += 1
            else
              tie_bests += 1
            timeline_count = ffrc_timeline_push(timeline_times, timeline_ranks, timeline_count, elapsed_s - timeline_start_s, gpu_rank)
            best = gpu_clone
            adopted = 1
      else
        exact_rejects += 1

    if adopted != 0
      saved = ffrc_dump_atomic(best, best_path, run_tag, round + 1) ## i64
      if saved < 1
        if tui != 0
          ccall("w_term_raw_disable")
        << "RECT_ERROR code=checkpoint-write tensor=" + tensor + " path=" + best_path
        return 2
      # Follow the new leader with one rotating island.  Every other island
      # keeps its current basin and is not reset by fleet-wide progress.
      rebase_lane = round % walkers ## i64
      rebased = ffrc_clone_exact(best, n, m, p, capacity, 85001 + round * 149, dslack, cycles, workq, wanderq)
      if rebased != nil
        states[rebase_lane] = rebased
        island_sources[rebase_lane] = seed_door + "/rebase-r" + ffr_best_rank(best).to_s()
        island_last_rank[rebase_lane] = ffr_best_rank(rebased)
        island_last_bits[rebase_lane] = ffr_best_bits(rebased)
        island_last_moves[rebase_lane] = ffr_moves(rebased)
        island_last_progress_ms[rebase_lane] = now_ms

    # TUI controls, polled between rounds while every island thread is joined
    # and the GPU epoch is drained (states are safe to mutate here).  Space
    # starts a fresh naive frontier and rank timeline; w reseeds the islands
    # on the campaign anchor; q / Ctrl-C (byte 3 in raw mode) = cooperative
    # stop, twice = force.
    if tui != 0
      key = ccall("w_input_poll", 0) ## i64
      keys_seen = 0 ## i64
      while key >= 0 && keys_seen < 8
        if key == 32
          naive_anchor = i64[state_size]
          naive_rank = ffr_init_naive_cap(naive_anchor, n, m, p, capacity, 86011 + round * 151, dslack, cycles, workq, wanderq) ## i64
          naive_best = nil
          if naive_rank > 0
            naive_best = ffrc_clone_exact(naive_anchor, n, m, p, capacity, 86013 + round * 151, dslack, cycles, workq, wanderq)
          if naive_best != nil
            best = naive_best
            timeline_start_s = elapsed_s
            timeline_count = 1
            timeline_times[0] = 0
            timeline_ranks[0] = ffr_best_rank(best)
            rank_level_count = ffrc_level_push(rank_levels, rank_ticks, 0, ffr_best_rank(best))
            bits_level_count = ffrc_level_push(bits_levels, bits_ticks, 0, ffr_best_bits(best))
            new_bests = 0
            tie_bests = 0
            cpu_drops = 0
            cpu_ties = 0
            rw = 0 ## i64
            while rw < walkers
              fresh = i64[state_size]
              fresh_rank = ffr_init_naive_cap(fresh, n, m, p, capacity, 86101 + round * 157 + rw * 977, dslack, cycles, workq, wanderq) ## i64
              if fresh_rank > 0
                states[rw] = fresh
                island_sources[rw] = seed_door + "/manual-naive"
                island_last_rank[rw] = ffr_best_rank(fresh)
                island_last_bits[rw] = ffr_best_bits(fresh)
                island_last_moves[rw] = ffr_moves(fresh)
                island_last_progress_ms[rw] = now_ms
              rw += 1
            reset_saved = ffrc_dump_atomic(best, best_path, run_tag, round + 200000) ## i64
            if reset_saved < 1
              status_degraded = 1
              flash_text = "fleet best reset to naive; checkpoint write failed"
            if reset_saved >= 1
              flash_text = "fleet best and rank timeline reset to naive (r" + ffr_best_rank(best).to_s() + ")"
          if naive_best == nil
            flash_text = "naive reseed failed exact best clone; fleet best unchanged"
          flash_until_ms = now_ms + 4000
        if key == 119 || key == 87
          rw = 0 ## i64
          while rw < walkers
            reseeded = ffrc_clone_exact(anchor, n, m, p, capacity, 87001 + round * 163 + rw * 991, dslack, cycles, workq, wanderq)
            if reseeded != nil
              states[rw] = reseeded
              island_sources[rw] = seed_door + "/manual-anchor"
              island_last_rank[rw] = ffr_best_rank(reseeded)
              island_last_bits[rw] = ffr_best_bits(reseeded)
              island_last_moves[rw] = ffr_moves(reseeded)
              island_last_progress_ms[rw] = now_ms
            rw += 1
          flash_text = "islands reseeded on the " + seed_door + " anchor (r" + ffr_best_rank(anchor).to_s() + ")"
          flash_until_ms = now_ms + 4000
        if key == 3 || key == 113 || key == 81
          if stop_key == 1
            ccall("w_term_raw_disable")
            exit(130)
          stop_key = 1
          flash_text = "stopping — draining the GPU epoch and saving state"
          flash_until_ms = now_ms + 10000
        keys_seen += 1
        key = ccall("w_input_poll", 0) ## i64

    sequence += 1
    status = ffrc_status_body("running", sequence, tensor, record, record_known, best, walkers, cpu_moves, cpu_ms, gpu_requested, gpu_supported, gpu_ready, lanes, gpu_moves, gpu_ms, gpu_failures, exact_rejects, elapsed_s)
    status_ok = ffrc_atomic_write(status_path, status, run_tag, sequence)
    if status_ok == 1
      last_status_ms = now_ms
    if status_ok == 0
      status_degraded = 1
    if quiet == 0 && tui == 0
      << "RECT_STATUS tensor=" + tensor + " round=" + round.to_s() + " rank=" + ffr_best_rank(best).to_s() + " bits=" + ffr_best_bits(best).to_s() + " cpu_moves=" + cpu_moves.to_s() + " gpu_moves=" + gpu_moves.to_s() + " exact_rejects=" + exact_rejects.to_s()
      flush()
    if tui != 0
      if ff_tui_heartbeat_due(last_render_ms, now_ms, 200) == 1
        last_render_ms = now_ms
        rank_level_count = ffrc_level_push(rank_levels, rank_ticks, rank_level_count, ffr_best_rank(best))
        bits_level_count = ffrc_level_push(bits_levels, bits_ticks, bits_level_count, ffr_best_bits(best))
        width = ccall("w_term_cols") ## i64
        if width < 60
          width = 60
        frame_rows = ffrc_frame_rows(tensor, seed_door, walkers, round, elapsed_s, cpu_moves + gpu_moves, record, record_known, best, states, island_rates, island_ages, island_sources, phase_moves, gpu_requested, gpu_supported, gpu_ready, lanes, gpu_seed_rank, gpu_candidates, gpu_rank_drops, gpu_density_improvements, gpu_reward_milli, gpu_exposure, gpu_ms, gpu_failures, cpu_moves, cpu_drops, cpu_ties, timeline_times, timeline_ranks, timeline_count, elapsed_s - timeline_start_s, status_degraded, last_status_ms, sequence, now_ms, rank_levels, rank_ticks, rank_level_count, bits_levels, bits_ticks, bits_level_count, new_bests, tie_bests, exact_rejects, dslack, flash_text, flash_until_ms, width)
        z = ffrc_render(frame_rows)

    round += 1
    if round >= max_rounds
      running = 0
    if max_secs > 0 && elapsed_s >= max_secs
      running = 0
    if stop_on_record != 0 && ffr_best_rank(best) < record
      running = 0
    if stop_key != 0
      running = 0
    if ccall("__w_interrupted") != 0
      running = 0

  if tui != 0
    ccall("w_term_raw_disable")
    << ""
    if stop_key != 0 || ccall("__w_interrupted") != 0
      << "  " + ff_tui_paint("interrupt — stopping the persistent GPU child and saving state (Ctrl-C again to force quit)", "1;33")
    flush()
  if persistent_active[0] != 0
    stopped = ffrc_persistent_stop(run_tag, tensor, persistent_processes, persistent_active, persistent_generations, persistent_lanes) ## i64
    if stopped == 0
      gpu_failures += 1
  final_ms = ccall("__w_clock_ms") ## i64
  final_elapsed_s = (final_ms - start_ms) / 1000 ## i64
  final_status = ffrc_status_body("stopped", sequence + 1, tensor, record, record_known, best, walkers, cpu_moves, cpu_ms, gpu_requested, gpu_supported, gpu_ready, lanes, gpu_moves, gpu_ms, gpu_failures, exact_rejects, final_elapsed_s)
  status_ok = ffrc_atomic_write(status_path, final_status, run_tag, sequence + 1)
  saved = ffrc_dump_atomic(best, best_path, run_tag, sequence + 100000) ## i64
  if saved < 1
    << "RECT_ERROR code=final-checkpoint tensor=" + tensor + " path=" + best_path
    return 2
  # A multi-shape parent owns the terminal and emits one atomic portfolio
  # frame/status record.  Suppress only the child summary in that mode; exact
  # failures still surface immediately through RECT_ERROR.
  if portfolio_child == 0
    << "RECT_RESULT tensor=" + tensor + " rank=" + ffr_best_rank(best).to_s() + " bits=" + ffr_best_bits(best).to_s() + " exact=" + ffr_verify_best_exact(best, n, m, p).to_s() + " path=" + best_path
  0
