# Native release/LTO smoke coverage for flipfleet_gpu_policy.w.
# Run: bin/tungsten --release --lto -o /tmp/ffgp benchmarks/matmul/metaflip/flipfleet_gpu_policy_test.w && /tmp/ffgp

use flipfleet_gpu_policy

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  << "PASS " + name

-> count_nonzero(values) (i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < 11
    if values[i] != 0
      count += 1
    i += 1
  count

eligible = i64[11]
weights = i64[11]
active3 = ffg_fill_profile(3, 0, eligible, weights)
check("profile.3.active", active3 == 6)
check("profile.3.symmetry off", eligible[2] == 0 && weights[2] == 0)
check("profile.3.zero break off", eligible[4] == 0 && weights[4] == 0)
check("profile.3.simd", weights[9] == 25)

eligible5 = i64[11]
weights5 = i64[11]
active5 = ffg_fill_profile(5, 1, eligible5, weights5)
check("profile.5.stable roles", active5 == 7)
check("profile.5.weights", weights5[0] == 15 && weights5[2] == 12 && weights5[10] == 4)

eligible5_no_c3 = i64[11]
weights5_no_c3 = i64[11]
active5_no_c3 = ffg_fill_profile(5, 0, eligible5_no_c3, weights5_no_c3)
check("profile.5.c3 gating", active5_no_c3 == 6 && eligible5_no_c3[2] == 0 && eligible5_no_c3[5] == 0 && eligible5_no_c3[6] == 0)

nprofile = 3 ## i64
while nprofile <= 7
  ep = i64[11]
  wp = i64[11]
  ap = i64[11]
  hc3 = 1 ## i64
  if nprofile < 5
    hc3 = 0
  ac = ffg_fill_profile(nprofile, hc3, ep, wp)
  okp = ffg_initial_allocate(4100, ep, wp, ap)
  check("profile.allocation.covered." + nprofile.to_s(), okp == 1)
  check("profile.allocation.quantized-budget." + nprofile.to_s(), ffg_lane_sum(ap) == 4096)
  rp = 0 ## i64
  while rp < 11
    if ep[rp] == 0 || wp[rp] == 0
      check("profile.off." + nprofile.to_s() + "." + rp.to_s(), ap[rp] == 0)
    if ep[rp] != 0 && wp[rp] > 0
      check("profile.floor." + nprofile.to_s() + "." + rp.to_s(), ap[rp] >= 32)
    rp += 1
  nprofile += 1

allocation = i64[11]
covered = ffg_initial_allocate(4096, eligible, weights, allocation)
check("initial.covered", covered == 1)
check("initial.exact lane sum", ffg_lane_sum(allocation) == 4096)
check("initial.quantized", allocation[0] % 32 == 0 && allocation[9] % 32 == 0)
check("initial.zero roles off", allocation[2] == 0 && allocation[4] == 0 && allocation[5] == 0 && allocation[6] == 0)
i = 0
while i < 11
  if eligible[i] != 0 && weights[i] > 0
    check("initial.floor." + i.to_s(), allocation[i] >= 32)
  i += 1

# Explicitly eligible but zero-weight stays disabled.
zero_eligible = i64[11]
zero_weights = i64[11]
zero_alloc = i64[11]
zero_eligible[0] = 1
zero_weights[0] = 10
zero_eligible[1] = 1
zero_weights[1] = 0
zcovered = ffg_initial_allocate(64, zero_eligible, zero_weights, zero_alloc)
check("zero weight off", zcovered == 1 && zero_alloc[0] == 64 && zero_alloc[1] == 0)

# Seven stable roles cannot all receive floors from six quanta.  The allocator
# uses every quantum but reports degraded coverage and drops the pool marker.
small_alloc = i64[11]
small_covered = ffg_initial_allocate(192, eligible5, weights5, small_alloc)
check("small.degraded", small_covered == 0)
check("small.spends budget", ffg_lane_sum(small_alloc) == 192)
check("small.six roles", count_nonzero(small_alloc) == 6)
check("small.drops lowest", small_alloc[10] == 0)

# Exposure and exact-candidate accounting.
epochs = i64[11]
lane_epochs = i64[11]
total_reward = i64[11]
epoch_reward = i64[11]
candidates = i64[11]
pareto = i64[11]
drops = i64[11]
density = i64[11]
epoch_reward[0] = 999
added = ffg_complete_epoch(allocation, eligible, epochs, lane_epochs, epoch_reward)
check("epoch.exposure sum", added == 128)
check("epoch.role exposure", epochs[0] == 1 && lane_epochs[0] == allocation[0] / 32)
check("epoch.reset reward", epoch_reward[0] == 0)

rank_reward = ffg_record_candidate(0, 93, 91, 1155, 1100, 1, 100, total_reward, epoch_reward, candidates, pareto, drops, density)
check("reward.rank dominates", rank_reward == 21549)
check("reward.rank counters", candidates[0] == 1 && pareto[0] == 1 && drops[0] == 1 && density[0] == 0)
check("reward.accumulates", total_reward[0] == 21549 && epoch_reward[0] == 21549)

density_reward = ffg_record_candidate(1, 93, 93, 1000, 900, 0, 0, total_reward, epoch_reward, candidates, pareto, drops, density)
check("reward.density bounded", density_reward == 200)
check("reward.density counter", density[1] == 1 && drops[1] == 0)

# Warm UCB allocation favors a productive role without sacrificing any floor.
warm_pulls = i64[11]
warm_reward = i64[11]
i = 0
while i < 11
  warm_pulls[i] = 100
  warm_reward[i] = 0
  i += 1
warm_reward[0] = 1000000
adaptive = i64[11]
adaptive_covered = ffg_adaptive_allocate(384, eligible5, weights5, warm_pulls, warm_reward, adaptive)
check("adaptive.covered", adaptive_covered == 1)
check("adaptive.sum", ffg_lane_sum(adaptive) == 384)
check("adaptive.productive extra", adaptive[0] > 32)
i = 0
while i < 11
  if eligible5[i] != 0 && weights5[i] > 0
    check("adaptive.floor." + i.to_s(), adaptive[i] >= 32)
  if eligible5[i] == 0 || weights5[i] == 0
    check("adaptive.off." + i.to_s(), adaptive[i] == 0)
  i += 1

# Cold adaptive state falls back to the evidence profile.
cold_pulls = i64[11]
cold_reward = i64[11]
cold_alloc = i64[11]
cold_covered = ffg_adaptive_allocate(4096, eligible5, weights5, cold_pulls, cold_reward, cold_alloc)
check("adaptive.cold profile", cold_covered == 1 && ffg_lane_sum(cold_alloc) == 4096)
check("adaptive.cold weights", cold_alloc[0] > cold_alloc[10])

# Equal reward/exposure spreads extra capacity through diminishing returns.
equal_pulls = i64[11]
equal_reward = i64[11]
equal_alloc = i64[11]
i = 0
while i < 11
  equal_pulls[i] = 100
  equal_reward[i] = 0
  i += 1
equal_ok = ffg_adaptive_allocate(704, eligible5, weights5, equal_pulls, equal_reward, equal_alloc)
check("adaptive.equal covered", equal_ok == 1 && ffg_lane_sum(equal_alloc) == 704)
min_equal = equal_alloc[0] ## i64
max_equal = equal_alloc[0] ## i64
i = 1
while i < 11
  if eligible5[i] != 0 && weights5[i] > 0
    if equal_alloc[i] < min_equal
      min_equal = equal_alloc[i]
    if equal_alloc[i] > max_equal
      max_equal = equal_alloc[i]
  i += 1
check("adaptive.diminishing spread", max_equal - min_equal <= 32)

none_eligible = i64[11]
none_weights = i64[11]
none_alloc = i64[11]
none_pulls = i64[11]
none_reward = i64[11]
none_ok = ffg_adaptive_allocate(4096, none_eligible, none_weights, none_pulls, none_reward, none_alloc)
check("adaptive.no roles", none_ok == 1 && ffg_lane_sum(none_alloc) == 0)

check("rebalance.not due", ffg_rebalance_due(1000, 1999, 1000) == 0)
check("rebalance.due", ffg_rebalance_due(1000, 2000, 1000) == 1)
proposed = i64[11]
not_due = ffg_maybe_rebalance(1000, 1500, 1000, 384, eligible5, weights5, warm_pulls, warm_reward, adaptive, proposed)
check("rebalance.not due copy", not_due == 0 && ffg_allocation_changed(adaptive, proposed) == 0)
current_equal = i64[11]
i = 0
while i < 11
  current_equal[i] = 32
  i += 1
due_changed = ffg_maybe_rebalance(1000, 2000, 1000, 384, eligible5, weights5, warm_pulls, warm_reward, current_equal, proposed)
check("rebalance.changed", due_changed == 2 && proposed[0] > 32)
too_small = ffg_maybe_rebalance(1000, 2000, 1000, 192, eligible5, weights5, warm_pulls, warm_reward, current_equal, proposed)
check("rebalance.floor failure", too_small == -1)

# Engine routing and role-specific profiles.
check("engine.generic", ffg_engine_kind(0) == 0 && ffg_engine_name(7) == "cal2zone")
check("engine.symmetry", ffg_engine_kind(2) == 1 && ffg_engine_name(2) == "c3-preserving")
check("engine.simd", ffg_engine_kind(9) == 2 && ffg_engine_name(9) == "cooperative-simd")
check("engine.pool", ffg_engine_kind(10) == 3 && ffg_engine_name(10) == "kernel-pool")
check("profile.generic values", ffg_cal2zone_workq(3) == 80000 && ffg_cal2zone_wanderq(3) == 25000 && ffg_cal2zone_wthr(3) == 4 && ffg_cal2zone_escapes(3) == -1)
check("profile.simd measured", ffg_simd_mode(5) == 1 && ffg_simd_mode(6) == 2)

calcmd = ffg_cal2zone_command("bin/gpu relay", "seed's.txt", "out.txt", "live.txt", 5, 3, 500000, 256, 96, 3)
check("command.cal2 quote", calcmd.include?("'bin/gpu relay'") && calcmd.include?("'seed'\"'\"'s.txt'"))
check("command.cal2 ABI", calcmd.include?("5 5 5 x 0 500000 20 8 80000 25000 4 256") && calcmd.ends_with?("'live.txt' 96 3"))
rankcmd = ffg_cal2zone_command("gpu", "seed", "out", "", 5, 0, 100, 32, 96, 0)
check("command.cal2 numeric default", rankcmd.ends_with?("'' 1 1"))
check("command.cal2 zero lanes", ffg_cal2zone_command("gpu", "seed", "out", "", 5, 3, 100, 0, 96, 3) == "")

symcmd = ffg_symmetry_command("c3", "seed", "out", 128)
check("command.symmetry ABI", symcmd == "'c3' 'seed' 'out' 128 2000 1 15 200")
simdcmd = ffg_simd_command("simd", "seed", "out", 96, 6)
check("command.simd ABI", simdcmd == "'simd' 'seed' 'out' 3 20000 1 4 2")
mitmcmd = ffg_mitm_command("flipfleet_mitm", "/tmp/seed file", "/tmp/out file", 5, 16, 700, 2, 9)
check("command.mitm native", mitmcmd == "'flipfleet_mitm' '/tmp/seed file' '/tmp/out file' 5 16 700 2 9" && !mitmcmd.include?("python"))

plan = i64[4]
dispatched = ffg_mitm_plan(32, 500000, 700, 4, plan)
check("mitm.logical cap", plan[0] == 131072)
check("mitm.diverse plan", plan[1] == 4 && plan[2] == 181 && plan[3] == 131044 && dispatched == plan[3])
check("mitm.nearby cycle", ffg_mitm_nearby(1) == 1 && ffg_mitm_nearby(2) == 2 && ffg_mitm_nearby(3) == 3 && ffg_mitm_nearby(4) == 1)
small_plan = i64[4]
small_dispatched = ffg_mitm_plan(1, 1, 3, 0, small_plan)
check("mitm.irreducible minimum", small_plan[0] == 1 && small_plan[1] == 1 && small_plan[2] == 4 && small_dispatched == 16)

<< "flipfleet_gpu_policy smoke: all checks passed"
