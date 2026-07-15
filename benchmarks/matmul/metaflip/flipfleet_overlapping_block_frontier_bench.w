# Reproducible real-frontier audit for support-guided overlapping block swaps.
#
# Usage:
#   flipfleet_overlapping_block_frontier_bench [N=0] [BANK=16] [SAMPLES=64] [TOP=12]
#
# N=0 runs 4x4, 6x6, and both rank-247 7x7 presentations.  SAMPLES is per
# axis.  The full-block branch is complete over the bounded support banks;
# only the generic four-cycle and pair-XOR branches are sampled.

use flipfleet_overlapping_block_frontier

-> ffobpfb_run(label, path, n, stable_leaves, bank_capacity, samples, top_capacity) (String String i64 Array i64 i64 i64) i64
  source = ffbc_load_exact(path, n, n, n, 512)
  if source == nil
    << "OVERLAP_BLOCK_FRONTIER_ERROR tensor=" + label + " error=load"
    return 0 - 1
  leaves = ffobpf_with_frontier_leaf(source, stable_leaves)
  ibank = i64[bank_capacity]
  jbank = i64[bank_capacity]
  kbank = i64[bank_capacity]
  icount = ffobpf_support_bank(source, 0, ibank) ## i64
  jcount = ffobpf_support_bank(source, 1, jbank) ## i64
  kcount = ffobpf_support_bank(source, 2, kbank) ## i64
  pairs = n * (n - 1) / 2 ## i64
  singleton_total = 3 * n * pairs * pairs ## i64

  cache_capacity = 8192 ## i64
  cache = FFOBPBlockCache.new(n, n, n, cache_capacity)
  full = i64[7]
  support = i64[8]
  started = ccall("__w_clock_ms") ## i64
  z = ffobpf_scan_full_replacements(source, leaves, ibank, icount, jbank, jcount, kbank, kcount, 16, cache, full) ## i64
  z = ffobpf_scan_support(source, leaves, ibank, icount, jbank, jcount, kbank, kcount, samples, top_capacity, cache, support)
  elapsed = ccall("__w_clock_ms") - started ## i64

  << "OVERLAP_BLOCK_FRONTIER_SUMMARY tensor=" + label + " source=r" + source.rank().to_s() + " singleton_complete=" + singleton_total.to_s() + " singleton_noop=" + singleton_total.to_s() + " support_banks=" + icount.to_s() + "/" + jcount.to_s() + "/" + kcount.to_s() + " full_identities=" + full[0].to_s() + " full_formula_pass=" + full[1].to_s() + " full_best_nominal=" + full[4].to_s() + " full_best_exact=" + full[3].to_s() + " full_axis_mode=" + full[5].to_s() + "/" + full[6].to_s() + " full_useful_gated=" + full[2].to_s() + " support_sampled=" + support[0].to_s() + " support_nonnoop=" + support[1].to_s() + " single_best_rank=" + support[2].to_s() + " single_macro=" + support[3].to_s() + " single_overlap=" + support[4].to_s() + " pair_macros=" + support[5].to_s() + " pair_best_rank=" + support[6].to_s() + " support_useful_gated=" + support[7].to_s() + " cache=" + cache.count().to_s() + "/" + cache_capacity.to_s() + " elapsed_ms=" + elapsed.to_s()
  full[2] + support[7]

av = argv()
requested_n = 0 ## i64
bank_capacity = 16 ## i64
samples = 64 ## i64
top_capacity = 12 ## i64
if av.size() > 0
  requested_n = av[0].to_i()
if av.size() > 1
  bank_capacity = av[1].to_i()
if av.size() > 2
  samples = av[2].to_i()
if av.size() > 3
  top_capacity = av[3].to_i()
if bank_capacity < 8
  bank_capacity = 8
if bank_capacity > 32
  bank_capacity = 32
if samples < 1
  samples = 1
if samples > 512
  samples = 512
if top_capacity < 1
  top_capacity = 1
if top_capacity > 32
  top_capacity = 32

root = "benchmarks/matmul/metaflip/"
stable_leaves = ffobpf_leaf_pool_2_to_8(root)
useful = 0 ## i64
if requested_n == 0 || requested_n == 4
  useful += ffobpfb_run("4x4-r47", root + "matmul_4x4_rank47_d450_gf2.txt", 4, stable_leaves, bank_capacity, samples, top_capacity)
if requested_n == 0 || requested_n == 6
  useful += ffobpfb_run("6x6-r153", root + "matmul_6x6_rank153_d2506_odd_parent3_gf2.txt", 6, stable_leaves, bank_capacity, samples, top_capacity)
if requested_n == 0 || requested_n == 7
  useful += ffobpfb_run("7x7-r247-d3098", root + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", 7, stable_leaves, bank_capacity, samples, top_capacity)
  useful += ffobpfb_run("7x7-r247-d3554", root + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, stable_leaves, bank_capacity, samples, top_capacity)
<< "OVERLAP_BLOCK_FRONTIER_DONE useful_gated=" + useful.to_s() + " bank=" + bank_capacity.to_s() + " samples_per_axis=" + samples.to_s() + " top=" + top_capacity.to_s()
