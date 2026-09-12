# Identical frozen 16-island corpus, alternating reference/optimized order.
use fixtures/basin_reference
use ../lib/metaflip/seeds/catalog

av = argv()
if av.size() != 2
  << "usage: basin_identity_bench n repetitions"
  exit(2)
n = av[0].to_i() ## i64
repetitions = av[1].to_i() ## i64
if n < 2 || n > 7 || repetitions < 1 || repetitions > 10000
  exit(2)
capacity = n * n * n + 64 ## i64
root = __DIR__ + "/../lib/metaflip/"
paths = ffp_frontier_seed_paths(n)
states = []
i = 0 ## i64
while i < 16
  state = i64[ffw_state_size(capacity)]
  z = ffw_load_scheme_cap(state, root + paths[i % paths.size()], n, capacity, 301 + i, 0, 1, 3, 5)
  if z < 1 || ffw_verify_best_exact(state, n) != 1
    exit(1)
  states.push(state)
  i += 1
stats = i64[ffn_basin_stats_words(16)]
round = 0 ## i64
while round < 6
  mode = round % 2 ## i64
  checksum = 0 ## i64
  start = ccall("__w_clock_ms") ## i64
  i = 0
  while i < repetitions
    if mode == 0
      z = ffbr_active_basin_stats(states, states[0], stats)
    else
      z = ffn_active_basin_stats(states, states[0], stats)
    checksum += stats[0] + stats[1] + stats[2] + stats[3]
    i += 1
  elapsed = ccall("__w_clock_ms") - start ## i64
  << "RESULT n=" + n.to_s() + " mode=" + mode.to_s() + " repeat=" + round.to_s() + " frames=" + repetitions.to_s() + " ms=" + elapsed.to_s() + " checksum=" + checksum.to_s()
  round += 1
