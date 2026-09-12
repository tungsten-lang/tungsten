# Presentation-only adapter for the packed worker. Use the same styling,
# column renderer, histories and synchronized frame writer as small shapes.
use ../tui

# Each lane is a joined-worker snapshot: best rank, current rank, moves,
# moves/sec, last improvement ms, snapshot ms, best density, accepts, rejects.
# Never inspect a worker's mutable tensor or counters from the render loop.
-> ffws_frame_rows(n, rank, density, moves, workers, round, elapsed_s, gpu, failures, sequence, last_status_ms, now_ms, drops, ties, accepted, rejected, dslack, lanes, rank_levels, rank_ticks, rank_count, bits_levels, bits_ticks, bits_count, timeline_times, timeline_ranks, timeline_count, cycle_caption, width, reference, seeds)
  inner = width - 2 ## i64
  rows = []
  state = ff_tui_health(failures, 0, 0, 0, last_status_ms, now_ms, 5000)
  age = ff_tui_pad_left(ff_tui_duration_ms(ff_tui_heartbeat_age_ms(last_status_ms, now_ms)), 5)
  dims = n.to_s() + "," + n.to_s() + "," + n.to_s()
  title = "  metaflip  <" + dims + "> GF(2)   " + state + " age " + age + "   seq " + sequence.to_s()
  painted = "  " + ff_tui_paint("metaflip", "1;33") + "  ⟨" + dims + "⟩ GF(2)   " + ff_tui_paint(state, ff_tui_health_code(state)) + ff_tui_dim(" age " + age + "   seq " + sequence.to_s())
  rows.push(ff_tui_fit(title, painted, width))

  objective = ff_tui_objective(rank, 0, 0, 0)
  if reference > 0
    objective = ff_tui_objective_compare(rank,reference,"reference")
  moves_text = ff_tui_compact_fixed(moves, 6)
  plains = ["  " + objective, "   density " + density.to_s(), "   moves " + moves_text, "   elapsed " + ff_tui_duration(elapsed_s), "   threads " + workers.to_s(), "   round " + round.to_s()]
  painteds = ["  " + ff_tui_paint(objective, "1;32"), "   " + ff_tui_dim("density") + " " + density.to_s(), "   " + ff_tui_dim("moves") + " " + moves_text, "   " + ff_tui_dim("elapsed") + " " + ff_tui_duration(elapsed_s), "   " + ff_tui_dim("threads") + " " + workers.to_s(), "   " + ff_tui_dim("round") + " " + round.to_s()]
  rows.push(ff_tui_join_fit(plains, painteds, width))
  spark_width = width - 32 ## i64
  if spark_width < 1
    spark_width = 1
  if spark_width > 120
    spark_width = 120
  if rank_count > 0
    rows.push("  " + ff_tui_dim("rank    ") + ff_tui_paint(ff_tui_spark_runs(rank_levels, rank_ticks, rank_count, spark_width), "32") + ff_tui_dim(" " + rank_levels[0].to_s() + "→" + rank.to_s()))
    rows.push("  " + ff_tui_dim("density ") + ff_tui_paint(ff_tui_spark_runs(bits_levels, bits_ticks, bits_count, spark_width), "33") + ff_tui_dim(" " + bits_levels[0].to_s() + "→" + density.to_s()))
  plains = ["  new-bests " + drops.to_s(), "   ties " + ties.to_s(), "   exact-rejects " + failures.to_s(), "   density-slack " + dslack.to_s()]
  painteds = ["  " + ff_tui_dim("new-bests") + " " + drops.to_s(), "   " + ff_tui_dim("ties") + " " + ties.to_s(), "   " + ff_tui_dim("exact-rejects") + " " + failures.to_s(), "   " + ff_tui_dim("density-slack") + " " + dslack.to_s()]
  rows.push(ff_tui_join_fit(plains, painteds, width))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("CPU islands (packed factors; independent basins)", width), "36"))
  lane = 0 ## i64
  while lane < workers
    at = lane * 9 ## i64
    idle = (now_ms - lanes[at+4]) / 1000 ## i64
    row = ff_tui_cpu_island_row(lane, "packed", "walk", rank, lanes[at], lanes[at+1], 0-1, 0-1, 0-1, lanes[at+2], lanes[at+3], idle, "packed/seed"+(lane % seeds).to_s(), "running", 0, 0, inner)
    code = ""
    if lanes[at] == rank
      code = "32"
    if idle > 300
      code = "33"
    rows.push("  " + ff_tui_paint(row, code))
    lane += 1
  snapshot_age = "-"
  if workers > 0
    snapshot_age = ff_tui_duration_ms(now_ms - lanes[5])
  rows.push("  " + ff_tui_dim(ff_tui_clip("Rates and ranks: completed epochs; snapshot age " + snapshot_age, inner)))

  rows.push("")
  gpu_title = "CPU-only profile (no specialized GPU worker)"
  if gpu == 0
    gpu_title = "CPU-only run (--no-gpu)"
  rows.push(ff_tui_paint(ff_tui_rule(gpu_title, width), "35"))
  rows.push("  " + ff_tui_dim(ff_tui_clip("GPU unavailable for packed square factors; CPU islands carry the campaign", inner)))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Diversity", width), "36"))
  rows.push("  " + ff_tui_clip(seeds.to_s()+" verified seeds; "+workers.to_s() + " RNG streams; term-set distance not collected", inner))
  rows.push("  " + ff_tui_dim(ff_tui_clip("Frontier/shoulder archives and refinement: unavailable on packed backend", inner)))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Effectiveness (exposure-normalized)", width), "36"))
  rows.push("  " + ff_tui_cpu_effectiveness("packed/flip-split", moves, drops, ties, 0, inner))
  rows.push("  " + ff_tui_dim(ff_tui_clip("pair flips: accept " + ff_tui_compact(accepted) + " / reject " + ff_tui_compact(rejected) + " (not record claims)", inner)))

  rows.push("")
  rows.push(ff_tui_paint(ff_tui_rule("Rank timeline (wall-time; lower rank is up; * density-only)", width), "36"))
  lines = ff_tui_timeline(timeline_times, timeline_ranks, timeline_count, elapsed_s, inner)
  i = 0 ## i64
  while i < lines.size()
    code = "32"
    if i == lines.size() - 1
      code = "2"
    rows.push("  " + ff_tui_paint(lines[i], code))
    i += 1
  if timeline_count <= 1
    rows.push("  " + ff_tui_dim(ff_tui_clip("no adoptions yet: a new best rank plots o, a density-only best plots *", inner)))
  rows.push("")
  rows.push("  " + ff_tui_dim(ff_tui_clip("rank = asymptotic cost; density = base-case ops (want lower)", inner)))
  rows.push("  " + ff_tui_dim(ff_tui_clip("n=next shape | q/Ctrl-C=checkpoint and stop", inner)))
  if cycle_caption != ""
    rows.push(ff_tui_clip(cycle_caption, width))
  rows
