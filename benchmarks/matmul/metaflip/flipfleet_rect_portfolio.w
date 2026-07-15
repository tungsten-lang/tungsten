# Adaptive multi-shape rectangular FlipFleet coordinator.
#
# One portfolio epoch runs the selected single-shape coordinators concurrently
# with disjoint CPU/GPU budgets. Each child owns an independent exact
# checkpoint, sticky-island population, GPU relay, and status files for the
# duration of the epoch. Reallocation happens only after every child reaches a
# clean round boundary. The next epoch is an intentional exact restart from
# that shape's checkpoint, refreshing basins without unsafe live migration.

use flipfleet_rect_campaign
use flipfleet_rect_portfolio_policy
use flipfleet_rect_portfolio_tui
use flipfleet_live_store

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
  "2x2x5,4x5x7,3x4x6,4x5x6,4x4x6,4x4x5,2x5x6,3x4x7,3x5x6"

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

# Load the exact checkpoint when present, otherwise the profile seed.  The
# output row is [rank,bits].  Under --naive the schoolbook seed is used only
# for epoch zero; later epochs recover the portfolio's own durable checkpoint.
-> ffrpo_load_metrics(tensor, repo_root, best_path, naive, output, offset) (String String String i64 i64[] i64) i64
  n = ffrp_n(tensor) ## i64
  m = ffrp_m(tensor) ## i64
  p = ffrp_p(tensor) ## i64
  if ffr_supported(n, m, p) == 0 || output.size() < offset + 2
    return 0
  capacity = ffr_default_capacity(n, m, p) ## i64
  state = i64[ffr_state_size(capacity)]
  rank = 0 - 1 ## i64
  if naive != 0
    rank = ffr_init_naive_cap(state, n, m, p, capacity, 91001 + offset, 4, 4, 1000, 250)
  if naive == 0
    checkpoint = read_file(best_path)
    if checkpoint != nil && checkpoint.size() > 0
      rank = ffr_load_scheme_cap(state, best_path, n, m, p, capacity, 91003 + offset, 4, 4, 1000, 250)
    if checkpoint == nil || checkpoint.size() == 0
      seed_path = repo_root + "/" + ffrp_seed_rel(n, m, p)
      rank = ffr_load_scheme_cap(state, seed_path, n, m, p, capacity, 91007 + offset, 4, 4, 1000, 250)
  if rank < 1 || ffr_verify_best_exact(state, n, m, p) == 0
    return 0
  output[offset] = ffr_best_rank(state)
  output[offset + 1] = ffr_best_bits(state)
  1

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
  if ffrc_dump_atomic(state, best_path, run_tag, nonce) < 1
    return 0
  1

-> ffrpo_spawn_shape(tensor, repo_root, best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, stop_on_record, naive_seed, exit_codes, elapsed_ms, slot) (String String String String String i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64 i64 i64[] i64[] i64)
  Thread.new ->
    started = ccall("__w_clock_ms") ## i64
    code = ffrc_run(tensor, repo_root, "", best_path, status_path, child_tag, walkers, steps, epoch_rounds, max_secs, dslack, cycles, 0, gpu_requested, gpu_lanes, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, 1, 0, stop_on_record, naive_seed, 1) ## i64
    exit_codes[slot] = code
    elapsed_ms[slot] = ccall("__w_clock_ms") - started
    true

-> ffrpo_any_alive(threads)
  i = 0 ## i64
  while i < threads.size()
    thread = threads[i]
    if thread != nil && thread.alive?
      return 1
    i += 1
  0

-> ffrpo_status_body(state_name, sequence, epoch, elapsed_s, total_j, total_gpu, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, exposure, failures, gpu_failures, scores)
  body = "schema=1 mode=rect-portfolio producer_state=" + state_name + " sequence=" + sequence.to_s()
  health = "ok"
  if degraded != 0
    health = "degraded"
  body = body + " epoch=" + epoch.to_s() + " elapsed=" + elapsed_s.to_s() + " cpu_lanes=" + total_j.to_s() + " gpu_lanes=" + total_gpu.to_s() + " shapes=" + labels.size().to_s() + " health=" + health + "\n"
  i = 0 ## i64
  while i < labels.size()
    combined_failures = failures[i] + gpu_failures[i] ## i64
    body = body + "shape=" + labels[i] + " ready=" + ready[i].to_s() + " cpu=" + cpu_allocation[i].to_s() + " gpu=" + gpu_allocation[i].to_s()
    body = body + " rank=" + ranks[i].to_s() + " bits=" + bits[i].to_s() + " drops=" + rank_drops[i].to_s() + " density=" + density_gains[i].to_s()
    body = body + " exposure=" + exposure[i].to_s() + " failures=" + combined_failures.to_s() + " cpu_failures=" + failures[i].to_s() + " gpu_failures=" + gpu_failures[i].to_s() + " score=" + scores[i].to_s() + "\n"
    i += 1
  body

-> ffrpo_gpu_allocate(total_lanes, epoch, policy, shapes, ready, rank_drops, density_gains, leverage, exposure, failures, allocation, scores) (i64 i64 String i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  count = shapes.size() ## i64
  units = total_lanes / 16 ## i64
  zero_gpu_discount = i64[count]
  unit_allocation = i64[count]
  used = ffrpp_allocate(units, epoch, shapes, ready, zero_gpu_discount, rank_drops, density_gains, leverage, exposure, failures, unit_allocation, scores) ## i64
  i = 0 ## i64
  while i < count
    allocation[i] = 0
    i += 1
  if used <= 0
    return 0
  if policy == "single"
    best = 0 - 1 ## i64
    i = 0
    while i < count
      if ready[i] != 0
        if best < 0 || scores[i] > scores[best]
          best = i
      i += 1
    if best >= 0
      allocation[best] = units * 16
      return allocation[best]
    return 0
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

-> ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)
  if status_degraded != 0
    return 1
  i = 0 ## i64
  while i < permanent_failure.size()
    if permanent_failure[i] != 0 || hard_degraded[i] != 0 || gpu_degraded[i] != 0
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
  title_plain = "  flipfleet  rectangular portfolio GF(2)   " + health
  title_painted = "  " + ff_tui_paint("flipfleet", "1;33") + "  rectangular portfolio GF(2)   " + ff_tui_paint(health, health_code)
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
  footer = ff_tui_clip("allocations change only at exact epoch boundaries · space=reset every shape to naive · q/Ctrl-C stops after the current epoch", inner)
  rows.push("  " + ff_tui_dim(footer))
  rows

# Run several exact rectangular campaigns concurrently. `max_epochs` counts
# portfolio reallocations; each shape keeps its sticky islands for
# `shape_epoch_rounds` ordinary rectangular rounds before the exact restart.
-> ffrpo_run(shape_spec, repo_root, state_dir, best_base, best_explicit, status_path, status_explicit, run_tag, total_j, steps, max_epochs, max_secs, shape_epoch_rounds, dslack, cycles, gpu_requested, total_gpu_lanes, gpu_policy, gpu_steps, gpu_epoch_rounds, gpu_binary, gpu_rebuild, quiet, tui, stop_on_record, naive_seed) (String String String String i64 String i64 String i64 i64 i64 i64 i64 i64 i64 i64 i64 String i64 i64 String i64 i64 i64 i64 i64 i64) i64
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
  display_exposure = i64[count]
  display_failures = i64[count]
  display_cpu_failures = i64[count]
  display_gpu_failures = i64[count]
  display_ages = i64[count]
  display_elapsed = i64[count]
  best_paths = []
  child_status_paths = []

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
    leverage[i] = ffrpp_default_leverage(shapes[i])
    gpu_supported[i] = ffrgb_supported(n, m, p)
    gpu_states[i] = 0 - 1
    if gpu_supported[i] != 0
      gpu_states[i] = 1
    loaded = ffrpo_load_metrics(tensor, repo_root, path, naive_seed, metrics, i * 2) ## i64
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
  degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, 0) ## i64
  status_degraded = 0 ## i64
  last_render_ms = 0 - 1 ## i64
  last_parent_status_ms = 0 - 1 ## i64
  flash_text = ""

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

    threads = []
    i = 0
    while i < count
      exit_codes[i] = 0
      child_elapsed_ms[i] = 0
      reset_children[i] = 0
      active[i] = 0
      thread = nil
      if cpu_allocation[i] > 0 && ready[i] != 0
        reset_children[i] = reset_pending[i]
        child_tag = run_tag + "_" + labels[i].replace("x", "") + "_e" + epoch.to_s()
        child_gpu = 0 ## i64
        if gpu_allocation[i] > 0 && gpu_sched_ready[i] != 0
          child_gpu = 1
        rebuild = 0 ## i64
        if epoch == 0 && gpu_rebuild != 0
          rebuild = 1
        cleared = write_file(child_status_paths[i], "")
        if cleared
          active[i] = 1
          thread = ffrpo_spawn_shape(labels[i], repo_root, best_paths[i], child_status_paths[i], child_tag, cpu_allocation[i], steps, shape_epoch_rounds, child_max_secs, dslack, cycles, child_gpu, gpu_allocation[i], gpu_steps, gpu_epoch_rounds, ffrpo_gpu_binary(gpu_binary, labels[i]), rebuild, stop_on_record, reset_children[i], exit_codes, child_elapsed_ms, i)
        if cleared == false
          exit_codes[i] = 2
      threads.push(thread)
      i += 1

    epoch_started_ms = ccall("__w_clock_ms") ## i64
    while ffrpo_any_alive(threads) != 0
      now_ms = ccall("__w_clock_ms") ## i64
      elapsed_s = (now_ms - start_ms) / 1000
      active_j = 0 ## i64
      active_gpu = 0 ## i64
      ready_count = ffrpp_ready_count(ready, count) ## i64
      i = 0
      while i < count
        thread = threads[i]
        active[i] = 0
        if thread != nil && thread.alive?
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
        i = 0
        while i < count
          display_ranks[i] = ranks[i]
          display_bits[i] = bits[i]
          display_rank_drops[i] = rank_drops[i]
          display_density_gains[i] = density_gains[i]
          display_rewards[i] = rewards[i]
          display_exposure[i] = exposure[i]
          display_cpu_failures[i] = failures[i]
          display_gpu_failures[i] = gpu_failures[i]
          display_failures[i] = failures[i] + gpu_failures[i]
          display_ages[i] = ages[i]
          display_elapsed[i] = run_elapsed[i]
          if active[i] != 0
            display_elapsed[i] += (now_ms - epoch_started_ms) / 1000
          if active[i] == 0 && threads[i] != nil
            display_elapsed[i] += child_elapsed_ms[i] / 1000

          # Child status is cleared before launch, so a non-empty body belongs
          # to this exact epoch. Poll it for honest live ranks/moves instead of
          # showing a frozen dashboard until all four child rounds drain.
          if threads[i] != nil
            live_body = read_file(child_status_paths[i])
            if live_body != nil && live_body.size() > 0
              live_cpu_moves = ffrpo_status_i64(live_body, "cpu_moves", 0) ## i64
              live_gpu_moves = ffrpo_status_i64(live_body, "gpu_moves", 0) ## i64
              live_cpu_ms = ffrpo_status_i64(live_body, "cpu_ms", 0) ## i64
              live_gpu_ms = ffrpo_status_i64(live_body, "gpu_ms", 0) ## i64
              live_gpu_failures = ffrpo_status_i64(live_body, "gpu_failures", 0) ## i64
              live_rank = ffrpo_status_i64(live_body, "best_rank", 0 - 1) ## i64
              live_bits = ffrpo_status_i64(live_body, "best_bits", 0 - 1) ## i64
              display_total_moves += live_cpu_moves + live_gpu_moves
              live_cpu_quanta = (live_cpu_ms + 99) / 100 ## i64
              live_gpu_quanta = 0 ## i64
              if gpu_allocation[i] > 0 && live_gpu_ms > 0
                live_gpu_quanta = ((gpu_allocation[i] + 31) / 32) * ((live_gpu_ms + 99) / 100)
              display_exposure[i] += live_cpu_quanta + live_gpu_quanta
              display_gpu_failures[i] += live_gpu_failures
              display_failures[i] = display_cpu_failures[i] + display_gpu_failures[i]
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
          i += 1

        degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)
        if heartbeat_due != 0
          sequence += 1
          live_status = ffrpo_status_body("running", sequence, epoch, elapsed_s, total_j, total_gpu_lanes, degraded, labels, ready, cpu_allocation, gpu_allocation, display_ranks, display_bits, display_rank_drops, display_density_gains, display_exposure, display_cpu_failures, display_gpu_failures, scores)
          status_ok = ffrc_atomic_write(status_path, live_status, run_tag + "_portfolio", sequence)
          last_parent_status_ms = now_ms
          if status_ok == 0
            status_degraded = 1
          if status_ok != 0
            status_degraded = 0
          degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)

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
      ccall("__w_sleep_ms", 50)

    i = 0
    while i < count
      thread = threads[i]
      if thread != nil
        joined = thread.join
      active[i] = 0
      i += 1

    now_ms = ccall("__w_clock_ms") ## i64
    elapsed_s = (now_ms - start_ms) / 1000
    record_hit = 0 ## i64
    i = 0
    while i < count
      if cpu_allocation[i] > 0 && ready[i] != 0
        child_body = read_file(child_status_paths[i])
        cpu_moves_epoch = ffrpo_status_i64(child_body, "cpu_moves", 0) ## i64
        gpu_moves_epoch = ffrpo_status_i64(child_body, "gpu_moves", 0) ## i64
        cpu_ms_epoch = ffrpo_status_i64(child_body, "cpu_ms", child_elapsed_ms[i] * cpu_allocation[i]) ## i64
        gpu_ms_epoch = ffrpo_status_i64(child_body, "gpu_ms", 0) ## i64
        gpu_failure_epoch = ffrpo_status_i64(child_body, "gpu_failures", 0) ## i64
        exact_rejects_epoch = ffrpo_status_i64(child_body, "exact_rejects", 0) ## i64
        failed = 0 ## i64
        if exit_codes[i] != 0 || child_body == nil || child_body.size() == 0 || exact_rejects_epoch > 0
          failed = 1
        if failed == 0
          new_metrics = ffrpo_load_metrics(labels[i], repo_root, best_paths[i], 0, metrics, i * 2) ## i64
          if new_metrics == 0
            failed = 1
        if failed != 0
          failures[i] += 1
          retry_epoch[i] = epoch + ffrpo_backoff(failures[i]) + 1
          hard_degraded[i] = 1
          ready[i] = 0
        if failed == 0
          hard_degraded[i] = 0
          shape_moves[i] += cpu_moves_epoch + gpu_moves_epoch
          total_moves += cpu_moves_epoch + gpu_moves_epoch
          cpu_quanta = (cpu_ms_epoch + 99) / 100 ## i64
          gpu_quanta = 0 ## i64
          if gpu_allocation[i] > 0 && gpu_ms_epoch > 0
            gpu_quanta = ((gpu_allocation[i] + 31) / 32) * ((gpu_ms_epoch + 99) / 100)
          exposure[i] += cpu_quanta + gpu_quanta
          run_elapsed[i] += child_elapsed_ms[i] / 1000
          if gpu_allocation[i] > 0
            if gpu_failure_epoch > 0
              gpu_failures[i] += gpu_failure_epoch
              gpu_retry_epoch[i] = epoch + ffrpo_backoff(gpu_failures[i]) + 1
              gpu_degraded[i] = 1
              gpu_sched_ready[i] = 0
              gpu_states[i] = 0
            if gpu_failure_epoch == 0
              gpu_degraded[i] = 0
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
    degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)
    status = ffrpo_status_body("running", sequence, epoch, elapsed_s, total_j, total_gpu_lanes, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, exposure, failures, gpu_failures, scores)
    status_ok = ffrc_atomic_write(status_path, status, run_tag + "_portfolio", sequence)
    last_parent_status_ms = now_ms
    if status_ok == 0
      status_degraded = 1
    if status_ok != 0
      status_degraded = 0
    degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)
    if quiet == 0 && tui == 0
      << ffrpp_report(epoch, shapes, ready, gpu_sched_ready, cpu_allocation, scores)
      i = 0
      while i < count
        combined_failures = failures[i] + gpu_failures[i] ## i64
        << "RECT_PORTFOLIO_STATUS shape=" + labels[i] + " epoch=" + epoch.to_s() + " cpu=" + cpu_allocation[i].to_s() + " gpu=" + gpu_allocation[i].to_s() + " rank=" + ranks[i].to_s() + " bits=" + bits[i].to_s() + " moves=" + shape_moves[i].to_s() + " failures=" + combined_failures.to_s() + " cpu_failures=" + failures[i].to_s() + " gpu_failures=" + gpu_failures[i].to_s()
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

  if tui != 0
    ccall("w_term_raw_disable")
    << ""
  final_ms = ccall("__w_clock_ms") ## i64
  final_elapsed_s = (final_ms - start_ms) / 1000 ## i64
  degraded = ffrpo_degraded_state(permanent_failure, hard_degraded, gpu_degraded, status_degraded)
  final_status = ffrpo_status_body("stopped", sequence + 1, epoch, final_elapsed_s, total_j, total_gpu_lanes, degraded, labels, ready, cpu_allocation, gpu_allocation, ranks, bits, rank_drops, density_gains, exposure, failures, gpu_failures, scores)
  z = ffrc_atomic_write(status_path, final_status, run_tag + "_portfolio", sequence + 1)
  result = "RECT_PORTFOLIO_RESULT epoch=" + epoch.to_s() + " elapsed=" + final_elapsed_s.to_s()
  i = 0
  while i < count
    result = result + " " + labels[i] + "=r" + ranks[i].to_s() + "/d" + bits[i].to_s()
    i += 1
  << result
  0
