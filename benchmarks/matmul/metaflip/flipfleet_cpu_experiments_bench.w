# Reproducible one-core overhead measurement for accepted-state cycle watch.

use metaflip_worker

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
baseline = i64[size]
watched = i64[size]
path = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"
loaded = ffw_load_scheme_cap(baseline, path, n, capacity, 71, 4, 4, 1000000, 250000) ## i64
if loaded < 1 || ffw_reseed_from(watched, baseline, 71) < 1
  << "flipfleet_cpu_experiments_bench: seed load failed"
  exit(1)

moves = 20000000 ## i64
t0 = ccall("__w_clock_ms") ## i64
z = ffw_walk(baseline, moves) ## i64
baseline_ms = ccall("__w_clock_ms") - t0 ## i64
recent = i64[512]
stats = i64[9]
t0 = ccall("__w_clock_ms")
z = ffw_walk_cycle_watch(watched, moves, recent, 512, stats)
watched_ms = ccall("__w_clock_ms") - t0
if baseline_ms < 1
  baseline_ms = 1
if watched_ms < 1
  watched_ms = 1
baseline_rate = moves * 1000 / baseline_ms ## i64
watched_rate = moves * 1000 / watched_ms ## i64
overhead = 0 ## i64
if baseline_rate > watched_rate
  overhead = (baseline_rate - watched_rate) * 100 / baseline_rate
<< "baseline=" + baseline_rate.to_s() + "/s watched=" + watched_rate.to_s() + "/s overhead=" + overhead.to_s() + "% unique=" + stats[2].to_s() + " repeats=" + stats[3].to_s() + " inverse=" + stats[4].to_s()
