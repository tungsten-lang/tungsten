# Real-frontier benchmark for the bounded global one-axis kernel shear.
#
# Usage:
#   flipfleet_kernel_shear_bench seed.txt n [plans=16] [max_work_words=30000000]
#
# Every plan assigns exactly one mutable axis to every live term, solves the
# complete one-bit factor-edit kernel, rejects no-ops and ordinary one-flip
# endpoints, then rebuilds and verifies the entire matrix-multiplication
# tensor.  The benchmark never mutates or publishes its input frontier.

use metaflip_worker
use flipfleet_kernel_shear

args = argv()
if args.size() < 2
  << "usage: flipfleet_kernel_shear_bench seed.txt n [plans] [max_work_words]"
  exit(2)

seed_path = args[0]
n = args[1].to_i() ## i64
plans = 16 ## i64
max_work_words = 30000000 ## i64
if args.size() > 2
  plans = args[2].to_i()
if args.size() > 3
  max_work_words = args[3].to_i()
if n < 3 || n > 7 || plans < 1 || plans > 256 || max_work_words < 1
  << "invalid benchmark bounds"
  exit(2)

capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
frontier = i64[state_size]
rank = ffw_load_scheme_cap(frontier, seed_path, n, capacity, 710071, 0, 1, 1, 1) ## i64
if rank < 2 || ffw_verify_current_exact(frontier, n) == 0
  << "invalid exact frontier"
  exit(2)

source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
if ffw_export_current(frontier, source_u, source_v, source_w) != rank
  << "frontier export failed"
  exit(2)

axes = i64[capacity]
out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
endpoint = i64[state_size]
source_density = fftc_density(source_u, source_v, source_w, rank) ## i64
work_words = ffks_work_words(rank, n * n) ## i64
hits = 0 ## i64
full_exact = 0 ## i64
rank_drops = 0 ## i64
density_better = 0 ## i64
best_rank = rank ## i64
best_density = source_density ## i64
dependencies = 0 ## i64
changed_total = 0 ## i64
started = ccall("__w_clock_ms") ## i64
plan = 0 ## i64
while plan < plans
  mode = plan ## i64
  nonce = 104729 + plan * 130363 ## i64
  if mode > 7
    mode = 7
  if ffks_fill_axis_plan(source_u, source_v, source_w, rank, mode, nonce, axes) != rank
    << "axis-plan construction failed"
    exit(2)
  meta = i64[8]
  found = ffks_find_novel_bounded(source_u, source_v, source_w, rank, axes, n * n, max_work_words, out_u, out_v, out_w, meta) ## i64
  dependencies += meta[2]
  if found == rank
    hits += 1
    changed_total += meta[3]
    changed_index = 0 ## i64
    while changed_index < rank
      if source_u[changed_index] != out_u[changed_index] || source_v[changed_index] != out_v[changed_index] || source_w[changed_index] != out_w[changed_index]
        << "KERNEL_SHEAR_DELTA plan=" + plan.to_s() + " term=" + changed_index.to_s() + " axis=" + axes[changed_index].to_s() + " old=" + source_u[changed_index].to_s() + "," + source_v[changed_index].to_s() + "," + source_w[changed_index].to_s() + " new=" + out_u[changed_index].to_s() + "," + out_v[changed_index].to_s() + "," + out_w[changed_index].to_s()
      changed_index += 1
    endpoint_rank = ffw_init_terms_cap(endpoint, out_u, out_v, out_w, rank, n, capacity, 720071 + plan * 17, 0, 1, 1, 1) ## i64
    endpoint_exact = 0 ## i64
    if endpoint_rank > 0 && ffw_verify_current_exact(endpoint, n) == 1
      endpoint_exact = 1
      full_exact += 1
      endpoint_density = ffw_current_bits(endpoint) ## i64
      if endpoint_rank < best_rank
        best_rank = endpoint_rank
        best_density = endpoint_density
      if endpoint_rank == best_rank && endpoint_density < best_density
        best_density = endpoint_density
      if endpoint_rank < rank
        rank_drops += 1
      if endpoint_rank == rank && endpoint_density < source_density
        density_better += 1
    << "KERNEL_SHEAR_HIT plan=" + plan.to_s() + " mode=" + mode.to_s() + " changed=" + meta[3].to_s() + " dependencies=" + meta[2].to_s() + " endpoint_rank=" + endpoint_rank.to_s() + " full_exact=" + endpoint_exact.to_s()
  plan += 1

elapsed = ccall("__w_clock_ms") - started ## i64
<< "KERNEL_SHEAR_BENCH n=" + n.to_s() + " rank=" + rank.to_s() + " plans=" + plans.to_s() + " hits=" + hits.to_s() + " full_exact=" + full_exact.to_s() + " rank_drops=" + rank_drops.to_s() + " density_better=" + density_better.to_s() + " best_rank=" + best_rank.to_s() + " best_density=" + best_density.to_s() + " source_density=" + source_density.to_s() + " changed_total=" + changed_total.to_s() + " dependencies=" + dependencies.to_s() + " work_words=" + work_words.to_s() + " elapsed_ms=" + elapsed.to_s()
