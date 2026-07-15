# Offline real-frontier audit for zero/duplicate-admitting kernel shears.
# Usage: flipfleet_kernel_shear_rankdrop_bench [only_n=0] [modes=8] [seed] [start_mode=0]

use flipfleet_kernel_shear_rankdrop

-> ffksrb_path(n) (i64)
  if n == 4
    return "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt"
  if n == 5
    return "benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt"
  if n == 6
    return "benchmarks/matmul/metaflip/matmul_6x6_rank153_d1860_global_isotropy_gf2.txt"
  if n == 7
    return "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
  ""

-> ffksrb_run(n, modes, path, start_mode) (i64 i64 String i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 99301 + n, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_current_exact(state, n) != 1
    << "KERNEL_SHEAR_RANKDROP_BENCH_ERROR n=" + n.to_s() + " load"
    return 0 - 1
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  if ffw_export_current(state, us, vs, ws) != rank
    return 0 - 1
  axes = i64[capacity]
  out_u = i64[capacity]
  out_v = i64[capacity]
  out_w = i64[capacity]
  best_rank = rank + 1 ## i64
  best_density = 9223372036854775807 ## i64
  mode = start_mode ## i64
  end_mode = start_mode + modes ## i64
  while mode < end_mode
    z = ffks_fill_axis_plan(us, vs, ws, rank, mode, 104729 + n * 1009 + mode * 130363, axes) ## i64
    meta = i64[16]
    started = ccall("__w_clock_ms") ## i64
    found = ffksr_find_best_bounded(us, vs, ws, rank, axes, n * n, 30000000, out_u, out_v, out_w, meta) ## i64
    elapsed = ccall("__w_clock_ms") - started ## i64
    full = 0 ## i64
    if found > 0
      endpoint = i64[ffw_state_size(capacity)]
      loaded = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, found, n, capacity, 99401 + n * 17 + mode, 0, 1, 1, 1) ## i64
      if loaded == found && ffw_verify_current_exact(endpoint, n) == 1
        full = 1
        if found < best_rank || (found == best_rank && meta[7] < best_density)
          best_rank = found
          best_density = meta[7]
    << "KERNEL_SHEAR_RANKDROP_RESULT n=" + n.to_s() + " mode=" + mode.to_s() + " source_rank=" + rank.to_s() + " source_density=" + meta[13].to_s() + " columns=" + meta[0].to_s() + " basis=" + meta[1].to_s() + " dependencies=" + meta[2].to_s() + " combinations=" + meta[15].to_s() + " best_local_gate=" + meta[3].to_s() + " rankdrops=" + meta[4].to_s() + " densitydrops=" + meta[5].to_s() + " found=" + found.to_s() + " density=" + meta[7].to_s() + " zeros=" + meta[9].to_s() + " duplicate_pairs=" + meta[10].to_s() + " full=" + full.to_s() + " status=" + meta[12].to_s() + " work_words=" + meta[11].to_s() + " elapsed_ms=" + elapsed.to_s()
    mode += 1
  shown_rank = rank ## i64
  shown_density = ffksr_density(us, vs, ws, rank) ## i64
  if best_rank <= rank
    shown_rank = best_rank
    shown_density = best_density
  << "KERNEL_SHEAR_RANKDROP_SUMMARY n=" + n.to_s() + " start_mode=" + start_mode.to_s() + " modes=" + modes.to_s() + " source_rank=" + rank.to_s() + " best_rank=" + shown_rank.to_s() + " best_density=" + shown_density.to_s()
  1

only_n = 0 ## i64
modes = 8 ## i64
override_path = ""
start_mode = 0 ## i64
if ARGV.size() > 0
  only_n = ARGV[0].to_i()
if ARGV.size() > 1
  modes = ARGV[1].to_i()
if ARGV.size() > 2
  override_path = ARGV[2]
if ARGV.size() > 3
  start_mode = ARGV[3].to_i()
if modes < 1
  modes = 1
if modes > 16
  modes = 16
if start_mode < 0
  start_mode = 0
if start_mode + modes > 16
  modes = 16 - start_mode
n = 4 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    path = ffksrb_path(n)
    if override_path.size() > 0
      path = override_path
    z = ffksrb_run(n, modes, path, start_mode) ## i64
  n += 1
