use flipfleet_rect_campaign

-> ffrct_expect(label, condition) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

failures = 0 ## i64

campaign_source = read_file("benchmarks/matmul/metaflip/flipfleet_rect_campaign.w")
failures += ffrct_expect("rect reject helper imported", campaign_source != nil && campaign_source.include?("use flipfleet_rect_gpu_reject"))
failures += ffrct_expect("committed rejects block epoch reuse", campaign_source.include?("sidecars_ready = ffrgr_prepare_worker_sidecars(gpu_output_path)") && campaign_source.include?("seeded > 0 && cleared && sidecars_ready != 0"))
failures += ffrct_expect("every completed cal2zone epoch harvests", campaign_source.include?("if gpu_thread != nil\n      gpu_internal_rejects = ffrgr_harvest"))
failures += ffrct_expect("internal reject accounting", campaign_source.include?("if gpu_reject_status\[0\] != 0\n        exact_rejects += 1\n        gpu_failures += 1\n        status_degraded = 1"))
failures += ffrct_expect("internal reject status telemetry", campaign_source.include?("gpu_degraded=\" + status_degraded.to_s()") && campaign_source.include?("gpu_internal_rejects=\" + gpu_internal_rejects.to_s()"))
failures += ffrct_expect("single-door GPU keeps fleet best", ffrc_gpu_seed_lane(1, 1, 4) == 0 - 1)
failures += ffrct_expect("multi-door GPU alternates fleet best", ffrc_gpu_seed_lane(0, 4, 4) == 0 - 1 && ffrc_gpu_seed_lane(2, 4, 4) == 0 - 1)
failures += ffrct_expect("multi-door GPU rotates nonleaders", ffrc_gpu_seed_lane(1, 4, 4) == 1 && ffrc_gpu_seed_lane(3, 4, 4) == 2 && ffrc_gpu_seed_lane(5, 4, 4) == 3 && ffrc_gpu_seed_lane(7, 4, 4) == 1)
failures += ffrct_expect("GPU door rotation clamps to walkers", ffrc_gpu_seed_lane(1, 4, 2) == 1 && ffrc_gpu_seed_lane(3, 4, 2) == 1)
failures += ffrct_expect("CPU balance CPU-only inert", ffrc_balanced_cpu_steps(500000, 50, 0, 500000) == 500000)
balanced1 = ffrc_balanced_cpu_steps(500000, 50, 400, 500000) ## i64
balanced2 = ffrc_balanced_cpu_steps(balanced1, 90, 400, 500000) ## i64
failures += ffrct_expect("CPU balance ramps", balanced1 == 875000 && balanced2 > balanced1)
failures += ffrct_expect("CPU balance absolute cap", ffrc_balanced_cpu_steps(16000000, 1, 120000, 500000) == 16000000)
failures += ffrct_expect("CPU balance shrinks", ffrc_balanced_cpu_steps(2000000, 800, 200, 500000) < 2000000)

root = "benchmarks/matmul/metaflip/"
n = 4 ## i64
m = 4 ## i64
p = 5 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
state = i64[ffr_state_size(capacity)]
rank = ffr_load_scheme_cap(state, root + "matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt", n, m, p, capacity, 901, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("445 exact density leader", rank == 60 && ffr_verify_best_exact(state, n, m, p) == 1 && ffr_best_bits(state) == 628)
legacy = i64[ffr_state_size(capacity)]
legacy_rank = ffr_load_scheme_cap(legacy, root + "matmul_4x4x5_rank60_d919_gf2.txt", n, m, p, capacity, 902, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("445 exact legacy frontier", legacy_rank == 60 && ffr_verify_best_exact(legacy, n, m, p) == 1 && ffr_best_bits(legacy) == 919)
failures += ffrct_expect("density leader improves a private door", ffrc_door_improvement(state, legacy, n, m, p) == 1)
failures += ffrct_expect("worse door cannot replace leader", ffrc_door_improvement(legacy, state, n, m, p) == 0)
failures += ffrct_expect("GPU door feedback is durable and private", campaign_source.include?("states\[alternate_lane\] = door_clone") && campaign_source.include?("best_path + \".gpu-door-\"") && campaign_source.include?("gpu_door_adoptions += 1"))

clone = ffrc_clone_exact(state, n, m, p, capacity, 903, 4, 8, 1000, 250)
failures += ffrct_expect("rectangular clone", clone != nil)
if clone != nil
  failures += ffrct_expect("clone keeps packed shape", ffr_shape_n(clone) == 4 && ffr_shape_m(clone) == 4 && ffr_shape_p(clone) == 5)
  failures += ffrct_expect("clone remains exact", ffr_verify_best_exact(clone, n, m, p) == 1)

# Exercise the same three-phase CPU epoch used by first-class rectangular
# dispatch without building or opening a Metal device.
phase = i64[3]
z = ffrp_campaign_budgets(10000, phase)
elapsed = i64[1]
thread = ffrc_spawn_cpu(clone, phase[0], phase[1], phase[2], elapsed, 0)
joined = thread.join
failures += ffrct_expect("CPU epoch joined", joined == true)
failures += ffrct_expect("CPU epoch exact", ffr_verify_best_exact(clone, n, m, p) == 1)
failures += ffrct_expect("CPU epoch covers work", ffw_work_moves(clone) > 0)
failures += ffrct_expect("CPU epoch covers wander", ffw_wander_moves(clone) > 0 && ffw_split_attempts(clone) > 0)

status = ffrc_status_body("running", 3, "4x4x5", 60, 1, clone, 2, 20000, elapsed[0], 1, 1, 1, 256, 5120000, 17, 0, 0, 2)
failures += ffrct_expect("rect status mode", status.include?("mode=rect") && status.include?("tensor=4x4x5"))
failures += ffrct_expect("rect status capabilities", status.include?("gpu_supported=1") && status.include?("gpu_lanes=256"))
failures += ffrct_expect("open profile strict target", status.include?("target=59"))
optimal_status = ffrc_status_body("running", 3, "2x3x4", 20, 1, clone, 2, 20000, elapsed[0], 1, 1, 1, 256, 5120000, 17, 0, 0, 2)
failures += ffrct_expect("proved profile does not advertise impossible target", optimal_status.include?("target=20"))

# Run-length sparkline history: repeats extend the last run, new values append.
levels = i64[256]
ticks = i64[256]
level_count = ffrc_level_push(levels, ticks, 0, 60) ## i64
level_count = ffrc_level_push(levels, ticks, level_count, 60)
level_count = ffrc_level_push(levels, ticks, level_count, 59)
failures += ffrct_expect("level runs compress", level_count == 2 && levels[0] == 60 && ticks[0] == 2 && levels[1] == 59 && ticks[1] == 1)
timeline_times = i64[256]
timeline_ranks = i64[256]
timeline_ranks[0] = 60
timeline_count = ffrc_timeline_push(timeline_times, timeline_ranks, 1, 12, 59) ## i64
failures += ffrct_expect("timeline event appended", timeline_count == 2 && timeline_times[1] == 12 && timeline_ranks[1] == 59)

# The shared-TUI frame builder is pure: assert dashboard content directly.
frame_states = []
frame_states.push(clone)
frame_rates = i64[1]
frame_ages = i64[1]
frame_sources = ["record/rebase-r60"]
frame_rates[0] = 5000000
frame_rows = ffrc_frame_rows("4x4x5", "record", 1, 7, 42, 5000000, 60, 1, clone, frame_states, frame_rates, frame_ages, frame_sources, phase, 1, 1, 1, 256, 60, 12, 1, 3, 9000, 10, 90000, 0, 40000, 1, 2, timeline_times, timeline_ranks, timeline_count, 42, 0, 900, 3, 1000, levels, ticks, level_count, levels, ticks, level_count, 1, 2, 0, 4, "resumed", 2000, 120)
frame_body = ""
fi = 0 ## i64
while fi < frame_rows.size()
  frame_body = frame_body + frame_rows[fi] + "\n"
  fi += 1
failures += ffrct_expect("frame title dims", frame_body.include?("⟨4,4,5⟩ GF(2)"))
failures += ffrct_expect("frame WR badge", frame_body.include?("WR 60"))
failures += ffrct_expect("frame objective", frame_body.include?("world record 60"))
failures += ffrct_expect("frame island row", frame_body.include?("w00 ") && frame_body.include?("record") && frame_body.include?("3-phase") && frame_body.include?("src:rebase-r60"))
failures += ffrct_expect("frame engine row", frame_body.include?("cal2zone") && frame_body.include?("256l") && frame_body.include?("cand 12"))
failures += ffrct_expect("frame flash visible", frame_body.include?("resumed"))
failures += ffrct_expect("frame timeline rule", frame_body.include?("Rank timeline"))
failures += ffrct_expect("frame key legend", frame_body.include?("space=reset naive") && frame_body.include?("q/Ctrl-C stops"))
failures += ffrct_expect("234 GPU enabled", ffrgb_supported(2, 3, 4) == 1)
failures += ffrct_expect("245 GPU enabled", ffrgb_supported(2, 4, 5) == 1)
failures += ffrct_expect("235 GPU enabled", ffrgb_supported(2, 3, 5) == 1)
failures += ffrct_expect("256 GPU enabled", ffrgb_supported(2, 5, 6) == 1)
failures += ffrct_expect("445 GPU enabled", ffrgb_supported(4, 4, 5) == 1)
failures += ffrct_expect("335 GPU enabled", ffrgb_supported(3, 3, 5) == 1)
failures += ffrct_expect("345 GPU enabled", ffrgb_supported(3, 4, 5) == 1)
failures += ffrct_expect("355 GPU enabled", ffrgb_supported(3, 5, 5) == 1)
failures += ffrct_expect("346 CPU only", ffrp_supported(3, 4, 6) == 1 && ffrgb_supported(3, 4, 6) == 0)
failures += ffrct_expect("455 CPU only", ffrp_supported(4, 5, 5) == 1 && ffrgb_supported(4, 5, 5) == 0)
failures += ffrct_expect("446 CPU only", ffrp_supported(4, 4, 6) == 1 && ffrgb_supported(4, 4, 6) == 0)
failures += ffrct_expect("456 CPU only", ffrp_supported(4, 5, 6) == 1 && ffrgb_supported(4, 5, 6) == 0)
failures += ffrct_expect("347 CPU only", ffrp_supported(3, 4, 7) == 1 && ffrgb_supported(3, 4, 7) == 0)
failures += ffrct_expect("356 CPU only", ffrp_supported(3, 5, 6) == 1 && ffrgb_supported(3, 5, 6) == 0)
failures += ffrct_expect("357 CPU only", ffrp_supported(3, 5, 7) == 1 && ffrgb_supported(3, 5, 7) == 0)
failures += ffrct_expect("458 CPU only", ffrp_supported(4, 5, 8) == 1 && ffrgb_supported(4, 5, 8) == 0)
failures += ffrct_expect("466 CPU only", ffrp_supported(4, 6, 6) == 1 && ffrgb_supported(4, 6, 6) == 0)
failures += ffrct_expect("468 CPU only", ffrp_supported(4, 6, 8) == 1 && ffrgb_supported(4, 6, 8) == 0)

# The d160 density leader, d170 public-basin continuation, and two independent
# fleet rediscoveries
# are the live upper frontier above the independently proved rank-23 lower
# bound. Exercise its exact catalog gate and the real runtime-generic CPU epoch,
# plus the first-class dimension-specialized Metal capability contract.
n235 = 2 ## i64
m235 = 3 ## i64
p235 = 5 ## i64
capacity235 = ffr_default_capacity(n235, m235, p235) ## i64
state235 = i64[ffr_state_size(capacity235)]
rank235 = ffr_load_scheme_cap(state235, ffrp_seed_rel(n235, m235, p235), n235, m235, p235, capacity235, 905, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("235 exact rank-25 seed", rank235 == 25 && ffr_best_bits(state235) == 160 && ffr_verify_best_exact(state235, n235, m235, p235) == 1)
failures += ffrct_expect("235 live target", ffrp_target_rank(n235, m235, p235) == 24 && ffrp_proven_optimal(n235, m235, p235) == 0)
failures += ffrct_expect("235 GPU specialization", ffrgb_supported(n235, m235, p235) == 1 && ffrgb_cap(n235, m235, p235) == 68 && ffrgb_geometry_valid(n235, m235, p235) == 1)
phase235 = i64[3]
z = ffrp_campaign_budgets(2000, phase235)
elapsed235 = i64[1]
thread235 = ffrc_spawn_cpu(state235, phase235[0], phase235[1], phase235[2], elapsed235, 0)
joined235 = thread235.join
failures += ffrct_expect("235 CPU epoch joined", joined235 == true)
failures += ffrct_expect("235 CPU epoch exact", ffr_verify_current_exact(state235, n235, m235, p235) == 1 && ffr_verify_best_exact(state235, n235, m235, p235) == 1)

# The high-leverage two-wide leaf is gated through the exact rank-47 catalog
# import, the runtime-generic CPU epoch, and its dimension-specialized Metal
# geometry before the profile can be advertised.
n256 = 2 ## i64
m256 = 5 ## i64
p256 = 6 ## i64
capacity256 = ffr_default_capacity(n256, m256, p256) ## i64
state256 = i64[ffr_state_size(capacity256)]
rank256 = ffr_load_scheme_cap(state256, ffrp_seed_rel(n256, m256, p256), n256, m256, p256, capacity256, 906, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("256 exact rank-47 seed", rank256 == 47 && ffr_best_bits(state256) == 438 && ffr_verify_best_exact(state256, n256, m256, p256) == 1)
failures += ffrct_expect("256 strict target", ffrp_target_rank(n256, m256, p256) == 46 && ffrp_proven_optimal(n256, m256, p256) == 0)
failures += ffrct_expect("256 GPU specialization", ffrgb_supported(n256, m256, p256) == 1 && ffrgb_cap(n256, m256, p256) == 92 && ffrgb_geometry_valid(n256, m256, p256) == 1)
phase256 = i64[3]
z = ffrp_campaign_budgets(2000, phase256)
elapsed256 = i64[1]
thread256 = ffrc_spawn_cpu(state256, phase256[0], phase256[1], phase256[2], elapsed256, 0)
joined256 = thread256.join
failures += ffrct_expect("256 CPU epoch joined", joined256 == true)
failures += ffrct_expect("256 CPU epoch exact", ffr_verify_current_exact(state256, n256, m256, p256) == 1 && ffr_verify_best_exact(state256, n256, m256, p256) == 1)

# Catalog-format `R u v w` seeds for the two sensitivity-selected profiles
# must pass the same exhaustive loader and finite CPU epoch as older profiles.
n346 = 3 ## i64
m346 = 4 ## i64
p346 = 6 ## i64
capacity346 = ffr_default_capacity(n346, m346, p346) ## i64
state346 = i64[ffr_state_size(capacity346)]
rank346 = ffr_load_scheme_cap(state346, ffrp_seed_rel(n346, m346, p346), n346, m346, p346, capacity346, 907, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("346 exact catalog seed", rank346 == 54 && ffr_best_bits(state346) == 826 && ffr_verify_best_exact(state346, n346, m346, p346) == 1)
phase346 = i64[3]
z = ffrp_campaign_budgets(2000, phase346)
elapsed346 = i64[1]
thread346 = ffrc_spawn_cpu(state346, phase346[0], phase346[1], phase346[2], elapsed346, 0)
joined346 = thread346.join
failures += ffrct_expect("346 CPU epoch joined", joined346 == true)
failures += ffrct_expect("346 CPU epoch exact", ffr_verify_current_exact(state346, n346, m346, p346) == 1 && ffr_verify_best_exact(state346, n346, m346, p346) == 1)

n456 = 4 ## i64
m456 = 5 ## i64
p456 = 6 ## i64
capacity456 = ffr_default_capacity(n456, m456, p456) ## i64
state456 = i64[ffr_state_size(capacity456)]
rank456 = ffr_load_scheme_cap(state456, ffrp_seed_rel(n456, m456, p456), n456, m456, p456, capacity456, 909, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("456 exact catalog seed", rank456 == 90 && ffr_best_bits(state456) == 975 && ffr_verify_best_exact(state456, n456, m456, p456) == 1)
phase456 = i64[3]
z = ffrp_campaign_budgets(2000, phase456)
elapsed456 = i64[1]
thread456 = ffrc_spawn_cpu(state456, phase456[0], phase456[1], phase456[2], elapsed456, 0)
joined456 = thread456.join
failures += ffrct_expect("456 CPU epoch joined", joined456 == true)
failures += ffrct_expect("456 CPU epoch exact", ffr_verify_current_exact(state456, n456, m456, p456) == 1 && ffr_verify_best_exact(state456, n456, m456, p456) == 1)

# A 4x5x7 campaign uses this same coordinator/CPU epoch path but must never
# advertise or attempt a Metal child.
n457 = 4 ## i64
m457 = 5 ## i64
p457 = 7 ## i64
capacity457 = ffr_default_capacity(n457, m457, p457) ## i64
state457 = i64[ffr_state_size(capacity457)]
rank457 = ffr_load_scheme_cap(state457, ffrp_seed_rel(n457, m457, p457), n457, m457, p457, capacity457, 911, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("457 exact seed", rank457 == 104 && ffr_best_bits(state457) == 1160 && ffr_verify_best_exact(state457, n457, m457, p457) == 1)
phase457 = i64[3]
z = ffrp_campaign_budgets(2000, phase457)
elapsed457 = i64[1]
thread457 = ffrc_spawn_cpu(state457, phase457[0], phase457[1], phase457[2], elapsed457, 0)
joined457 = thread457.join
failures += ffrct_expect("457 CPU epoch joined", joined457 == true)
failures += ffrct_expect("457 CPU epoch exact", ffr_verify_current_exact(state457, n457, m457, p457) == 1 && ffr_verify_best_exact(state457, n457, m457, p457) == 1)
failures += ffrct_expect("457 CPU only", ffrp_supported(n457, m457, p457) == 1 && ffrgb_supported(n457, m457, p457) == 0)

# The widest new p=8 profile exercises the four-bit shape header through the
# real threaded campaign epoch, not only through the standalone worker test.
n468 = 4 ## i64
m468 = 6 ## i64
p468 = 8 ## i64
capacity468 = ffr_default_capacity(n468, m468, p468) ## i64
state468 = i64[ffr_state_size(capacity468)]
rank468 = ffr_load_scheme_cap(state468, ffrp_seed_rel(n468, m468, p468), n468, m468, p468, capacity468, 913, 4, 8, 1000, 250) ## i64
failures += ffrct_expect("468 exact density leader", rank468 == 140 && ffr_best_bits(state468) == 1748 && ffr_verify_best_exact(state468, n468, m468, p468) == 1)
phase468 = i64[3]
z = ffrp_campaign_budgets(2000, phase468)
elapsed468 = i64[1]
thread468 = ffrc_spawn_cpu(state468, phase468[0], phase468[1], phase468[2], elapsed468, 0)
joined468 = thread468.join
failures += ffrct_expect("468 CPU epoch joined", joined468 == true)
failures += ffrct_expect("468 CPU epoch exact", ffr_verify_current_exact(state468, n468, m468, p468) == 1 && ffr_verify_best_exact(state468, n468, m468, p468) == 1)
failures += ffrct_expect("468 CPU only", ffrgb_supported(n468, m468, p468) == 0)

# A CPU-only profile's frame advertises expected capability, not a failure.
cpu_only_states = []
cpu_only_states.push(state457)
cpu_only_rows = ffrc_frame_rows("4x5x7", "record", 1, 7, 42, 2000, 104, 1, state457, cpu_only_states, frame_rates, frame_ages, frame_sources, phase457, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40000, 0, 0, timeline_times, timeline_ranks, 1, 42, 0, 900, 3, 1000, levels, ticks, 0, levels, ticks, 0, 0, 0, 0, 4, "", 0, 120)
cpu_only_body = ""
fi = 0
while fi < cpu_only_rows.size()
  cpu_only_body = cpu_only_body + cpu_only_rows[fi] + "\n"
  fi += 1
failures += ffrct_expect("cpu-only section honest", cpu_only_body.include?("CPU-only profile") && !cpu_only_body.include?("cal2zone build failed"))

if failures == 0
  << "PASS flipfleet rectangular campaign"
  exit(0)
<< "FAIL flipfleet rectangular campaign failures=" + failures.to_s()
exit(1)
