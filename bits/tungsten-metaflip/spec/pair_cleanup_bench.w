# Bounded, one-thread admission timings; no fleet, GPU, or search subprocess.
use ../lib/metaflip/fleet/pair_cleanup

-> pc_bench(n, m, p, rectangular, filename) (i64 i64 i64 i64 String) i64
  capacity = ffw_default_capacity(n) ## i64
  if rectangular != 0
    capacity = ffr_default_capacity(n, m, p)
  st = i64[ffw_state_size(capacity)]
  path = __DIR__ + "/../lib/metaflip/seeds/gf2/" + filename
  loaded = 0 ## i64
  if rectangular == 0
    loaded = ffw_load_scheme_cap(st, path, n, capacity, 17, 8, 3, 1000, 2000)
  else
    loaded = ffr_load_scheme_cap(st, path, n, m, p, capacity, 17, 8, 3, 1000, 2000)
  if loaded < 1
    << "FAIL benchmark seed " + filename
    return 1
  words = ffpc_scratch_words(capacity) ## i64
  work = i64[words]
  parity_words = ffw_verify_scratch_words(n, m, p) ## i64
  parity = i64[parity_words]
  checksum = 0 ## i64
  ordinary_ns = 0 ## i64
  cleanup_ns = 0 ## i64
  combined_ns = 0 ## i64
  trial = 0 ## i64
  while trial < 68
    # Alternate gate order to avoid consistently warming just one arm.
    arm = 0 ## i64
    while arm < 2
      started = ccall_nobox("__w_clock_ns_raw") ## i64
      if (arm + trial) % 2 == 0
        exact = 0 ## i64
        if rectangular == 0
          exact = ffw_verify_best_exact_scratch(st, n, parity, parity_words)
        else
          exact = ffr_verify_best_exact_scratch(st, n, m, p, parity, parity_words)
        elapsed = ccall_nobox("__w_clock_ns_raw") - started ## i64
        if exact != 1
          return 1
        if trial >= 4
          ordinary_ns += elapsed
      else
        cleaned = ffpc_gate_best(st, n, m, p, rectangular, work, words, parity, parity_words) ## i64
        elapsed = ccall_nobox("__w_clock_ns_raw") - started ## i64
        if cleaned != loaded
          << "FAIL benchmark requires a pair-free control"
          return 1
        if trial >= 4
          combined_ns += elapsed
      arm += 1
    i = 0 ## i64
    while i < loaded
      work[i] = st[st[47] + i]
      work[capacity + i] = st[st[48] + i]
      work[2 * capacity + i] = st[st[49] + i]
      i += 1
    started = ccall_nobox("__w_clock_ns_raw") ## i64
    checksum += ffpc_reduce(work, words, capacity, loaded, 0, 1, 2)
    elapsed = ccall_nobox("__w_clock_ns_raw") - started ## i64
    if trial >= 4
      cleanup_ns += elapsed
    trial += 1
  << "PAIR_CLEANUP_BENCH shape=" + n.to_s() + "x" + m.to_s() + "x" + p.to_s() + " rank=" + loaded.to_s() + " repeats=64 gate_ns=" + (ordinary_ns / 64).to_s() + " cleanup_only_ns=" + (cleanup_ns / 64).to_s() + " combined_gate_ns=" + (combined_ns / 64).to_s() + " scratch_bytes=" + (words * 8).to_s()
  if checksum != loaded * 68
    return 1
  0

failed = pc_bench(5, 5, 5, 0, "matmul_5x5_rank93_d967_four_split_control_gf2.txt") ## i64
failed += pc_bench(7, 7, 7, 0, "matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt")
failed += pc_bench(2, 5, 6, 1, "matmul_2x5x6_rank47_d438_orbit_door_gf2.txt")
if failed != 0
  exit(1)
