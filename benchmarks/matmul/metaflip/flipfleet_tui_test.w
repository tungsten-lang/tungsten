use flipfleet_tui

failures = 0 ## i64

-> fft_expect(label, condition) i64
  if !condition
    << "FAIL " + label
    return 1
  0

failures += fft_expect("health live", ff_tui_health(0, 0, 0, 0, 900, 1000, 500) == "LIVE")
failures += fft_expect("health degraded", ff_tui_health(0, 0, 0, 1, 900, 1000, 500) == "DEGRADED")
failures += fft_expect("health stale", ff_tui_health(0, 0, 0, 0, 0, 1000, 500) == "STALE")
failures += fft_expect("health compiling precedence", ff_tui_health(0, 0, 1, 1, 0, 1000, 500) == "COMPILING")
failures += fft_expect("health done precedence", ff_tui_health(0, 1, 1, 1, 0, 1000, 500) == "DONE")
failures += fft_expect("health failed precedence", ff_tui_health(1, 1, 1, 1, 0, 1000, 500) == "FAILED")

known = ff_tui_objective(92, 93, 1, 0)
baseline = ff_tui_objective(342, 343, 0, 0)
matched = ff_tui_objective(93, 93, 1, 0)
failures += fft_expect("honest world record beat", known.include?("beats world record 93 by 1"))
failures += fft_expect("honest world record match", matched.include?("matches world record 93"))
failures += fft_expect("honest baseline", baseline.include?("beats configured baseline 343 by 1"))
failures += fft_expect("WR badge known", ff_tui_record_badge(93, 1) == "WR 93")
failures += fft_expect("WR badge baseline", ff_tui_record_badge(343, 0) == "target 343")
failures += fft_expect("WR badge absent", ff_tui_record_badge(0, 0) == "")
cpu = ff_tui_cpu_island_row(3, "near1", "balanced", 23, 24, 25, 3, 12345, 8, 2500000, 1000000, 2, "near1/bank7", "running", 125000000, 25000000, 120)
failures += fft_expect("cpu id column", cpu.starts_with?("w03 "))
failures += fft_expect("cpu sticky door", cpu.include?("near1"))
failures += fft_expect("cpu zone", cpu.include?("balanced"))
failures += fft_expect("cpu current/best rank", cpu.include?("r25/r24"))
failures += fft_expect("cpu delta", cpu.include?("+1"))
failures += fft_expect("cpu zone budgets", cpu.include?("W125M/25M"))
failures += fft_expect("cpu basin digest", cpu.include?("#12345"))
failures += fft_expect("cpu basin distance", cpu.include?("d8"))
failures += fft_expect("cpu seed provenance", cpu.include?("src:bank7"))

dead = ff_tui_cpu_island_row(4, "near1", "short", 23, 24, 0, 3, 67890, 12, 2500000, 1000000, 2, "", "exited", 0, 0, 120)
failures += fft_expect("cpu dead island flag", dead.include?("!exited"))

gpu = ff_tui_gpu_role_row("compose", 320, 25, "split+split", 7, 2, 1, 3, 9000, 10, 0, 0, 160)
gpu_failed = ff_tui_gpu_role_row("compose", 320, 25, "split+split", 7, 2, 1, 3, 9000, 10, 2, 0, 160)
failures += fft_expect("gpu role column", gpu.starts_with?("compose "))
failures += fft_expect("gpu lanes", gpu.include?("320l"))
failures += fft_expect("gpu seed", gpu.include?("r25"))
failures += fft_expect("gpu outcomes", gpu.include?("cand 7"))
failures += fft_expect("gpu pareto", gpu.include?("P2"))
failures += fft_expect("gpu normalized reward", gpu.include?("reward/lane-100ms"))
failures += fft_expect("gpu recipe last", gpu.include?("split+split"))
failures += fft_expect("gpu failure column stable width", gpu.size() == gpu_failed.size())
failures += fft_expect("gpu failure visible", gpu_failed.include?("fail2"))
pool_pair_a = ff_tui_gpu_pool_pair("defect-rminus1", 1, 1, "mitm-5to4", 1, 1, 80)
pool_pair_b = ff_tui_gpu_pool_pair("xor-6to5", 1, 1, "xor-7to6", 0, 1, 80)
failures += fft_expect("gpu pool first simultaneous active", pool_pair_a.include?("● defect-rminus1"))
failures += fft_expect("gpu pool second simultaneous active", pool_pair_a.include?("● mitm-5to4"))
failures += fft_expect("gpu pool third simultaneous active", pool_pair_b.include?("● xor-6to5"))
failures += fft_expect("gpu pool ready inactive marker", pool_pair_b.include?("· xor-7to6"))
failures += fft_expect("gpu pool ready inactive dimmed", pool_pair_b.include?("\e[2m· xor-7to6"))
pool_active_cell = ff_tui_gpu_pool_cell("lifted-identity", 1, 1, 40)
pool_inactive_cell = ff_tui_gpu_pool_cell("lifted-identity", 0, 1, 40)
pool_unavailable_cell = ff_tui_gpu_pool_cell("orbit-split", 0, 0, 40)
failures += fft_expect("gpu pool active visible-width padding", pool_active_cell == "● lifted-identity" + (" " * 23))
failures += fft_expect("gpu pool inactive visible-width padding", pool_inactive_cell == "\e[2m· lifted-identity" + (" " * 23) + "\e[0m")
failures += fft_expect("gpu pool unavailable visible-width padding", pool_unavailable_cell == "\e[2m· orbit-split unavailable" + (" " * 15) + "\e[0m")

effect = ff_tui_cpu_effectiveness("near1/balanced", 2000000000, 1, 2, 2, 120)
failures += fft_expect("cpu normalized yield", effect.include?("2.50 productive/B"))

times = i64[4]
ranks = i64[4]
times[0] = 0
ranks[0] = 26
times[1] = 10
ranks[1] = 25
times[2] = 10
ranks[2] = 25
times[3] = 90
ranks[3] = 23
timeline = ff_tui_timeline(times, ranks, 4, 100, 80)
failures += fft_expect("timeline rows", timeline.size >= 5)
failures += fft_expect("lower rank up", timeline[0].starts_with?("r23"))
failures += fft_expect("wall time axis", timeline[timeline.size - 1].include?("1m40s"))

failures += fft_expect("paint wraps", ff_tui_paint("x", "32") == "\e[32mx\e[0m")
failures += fft_expect("paint empty code", ff_tui_paint("x", "") == "x")
failures += fft_expect("dim wraps", ff_tui_dim("x") == "\e[2mx\e[0m")
failures += fft_expect("health code live", ff_tui_health_code("LIVE") == "32")
failures += fft_expect("health code stale", ff_tui_health_code("STALE") == "31")
failures += fft_expect("health code failed", ff_tui_health_code("FAILED") == "1;31")

sv = i64[3]
sv[0] = 10
sv[1] = 5
sv[2] = 0
failures += fft_expect("spark shape", ff_tui_spark(sv, 3, 0, 10, 10) == "█▄▁")
failures += fft_expect("spark window", ff_tui_spark(sv, 3, 0, 10, 2) == "▄▁")
failures += fft_expect("spark empty", ff_tui_spark(sv, 0, 0, 10, 10) == "")

run_levels = i64[3]
run_ticks = i64[3]
run_levels[0] = 125
run_ticks[0] = 1
run_levels[1] = 100
run_ticks[1] = 20
run_levels[2] = 93
run_ticks[2] = 500
failures += fft_expect("spark runs pseudo-proportional", ff_tui_spark_runs(run_levels, run_ticks, 3, 20) == "█▂▂▁▁▁")
failures += fft_expect("spark runs keeps newest", ff_tui_spark_runs(run_levels, run_ticks, 3, 4) == "▂▁▁▁")
failures += fft_expect("spark runs single level", ff_tui_spark_runs(run_levels, run_ticks, 1, 20) == "▁")

failures += fft_expect("compact fixed decimal", ff_tui_compact_fixed(10000000000, 6) == " 10.0B")
failures += fft_expect("compact fixed small", ff_tui_compact_fixed(874, 6) == "   874")

failures += fft_expect("rule fill", ff_tui_rule("CPU", 12) == "── CPU ─────")
failures += fft_expect("rule narrow", ff_tui_rule("CPU islands", 6) == "CPU i~")
failures += fft_expect("fit painted", ff_tui_fit("abc", "PAINTED", 5) == "PAINTED")
failures += fft_expect("fit fallback", ff_tui_fit("abcdefgh", "PAINTED", 5) == "abcd~")

join_plains = ["A", "BB", "CCC"]
join_painteds = ["a", "b", "c"]
failures += fft_expect("join fit drops tail", ff_tui_join_fit(join_plains, join_painteds, 3) == "ab")
failures += fft_expect("join fit keeps all", ff_tui_join_fit(join_plains, join_painteds, 10) == "abc")
failures += fft_expect("join fit clips first", ff_tui_join_fit(["ABCDEF"], ["x"], 4) == "ABC~")

if failures > 0
  << "flipfleet_tui_test: " + failures.to_s + " failure(s)"
  exit(1)
<< "flipfleet_tui_test: all checks passed"
