# Bounded CPU benchmark on a planted reject derived from a checked-in exact
# frontier.  Usage:
#   flipfleet-syndrome-repair-bench [n=4] [mode=3] [max_work_words=4000000]
#
# Mode 3 is the exact W-only repair lane.  Mode 0 builds the larger all-axis
# system.  The benchmark always prints projected memory for both so 6x6/7x7
# can be assessed without allocating their much larger elimination tables.

use flipfleet_syndrome_repair

-> ffsrb_source_path(n) (i64)
  if n == 3
    return "benchmarks/matmul/metaflip/matmul_3x3_rank23_d139_gf2.txt"
  if n == 4
    return "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt"
  if n == 5
    return "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt"
  if n == 6
    return "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2502_gf2.txt"
  if n == 7
    return "benchmarks/matmul/metaflip/matmul_7x7_rank248_d2952_sedoglavic_gf2.txt"
  ""

-> ffsrb_copy(source, target, count) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target[i] = source[i]
    i += 1
  count

-> ffsrb_two_absent_bits(value, dim) (i64 i64) i64
  mask = 0 ## i64
  count = 0 ## i64
  bit = 0 ## i64
  while bit < dim && count < 2
    if ((value >> bit) & 1) == 0
      mask = mask | (1 << bit)
      count += 1
    bit += 1
  if count < 2
    bit = 0
    while bit < dim && count < 2
      if ((mask >> bit) & 1) == 0
        trial = mask | (1 << bit) ## i64
        if (value ^ trial) != 0
          mask = trial
          count += 1
      bit += 1
  mask

-> ffsrb_mib_tenths(words) (i64) i64
  (words * 80 + 524287) / 1048576

args = argv()
n = 4 ## i64
mode = 3 ## i64
max_work_words = 4000000 ## i64
if args.size() > 0
  n = args[0].to_i()
if args.size() > 1
  mode = args[1].to_i()
if args.size() > 2
  max_work_words = args[2].to_i()
path = ffsrb_source_path(n)
if path == "" || mode < 0 || mode > 6
  << "usage: flipfleet-syndrome-repair-bench [n=3..7] [mode=0..6] [max_work_words]"
  exit(1)

capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, path, n, capacity, 44017, 4, 2, 1000, 250) ## i64
if rank < 1 || ffw_verify_current_exact(state, n) != 1
  << "source did not load exactly: " + path
  exit(1)
source_u = i64[capacity]
source_v = i64[capacity]
source_w = i64[capacity]
z = ffw_export_current(state, source_u, source_v, source_w) ## i64
bad_u = i64[capacity]
bad_v = i64[capacity]
bad_w = i64[capacity]
z = ffsrb_copy(source_u, bad_u, rank)
z = ffsrb_copy(source_v, bad_v, rank)
z = ffsrb_copy(source_w, bad_w, rank)
toggle = ffsrb_two_absent_bits(bad_w[0], n * n) ## i64
if ffw_popcount(toggle) != 2 || (bad_w[0] ^ toggle) == 0
  << "could not plant a two-bit W reject"
  exit(1)
bad_w[0] = bad_w[0] ^ toggle

words = ffsr_tensor_words(n) ## i64
syndrome = i64[words]
a_slices = i64[n * n]
b_slices = i64[n * n]
c_slices = i64[n * n]
syndrome_meta = i64[10]
t0 = ccall("__w_clock_ms") ## i64
weight = ffsr_build_syndrome(bad_u, bad_v, bad_w, rank, n, syndrome, a_slices, b_slices, c_slices, syndrome_meta) ## i64
t1 = ccall("__w_clock_ms") ## i64

axis_words = ffsr_work_words(rank, n, 3) ## i64
all_words = ffsr_work_words(rank, n, 0) ## i64
<< "SYNDROME_REPAIR_BENCH n=" + n.to_s() + " rank=" + rank.to_s() + " weight=" + weight.to_s() + " slices=" + syndrome_meta[3].to_s() + "/" + syndrome_meta[4].to_s() + "/" + syndrome_meta[5].to_s() + " syndrome_ms=" + (t1 - t0).to_s()
<< "  projected axis_words=" + axis_words.to_s() + " axis_mib_tenths=" + ffsrb_mib_tenths(axis_words).to_s() + " all_words=" + all_words.to_s() + " all_mib_tenths=" + ffsrb_mib_tenths(all_words).to_s()

if ffsr_work_words(rank, n, mode) > max_work_words
  << "  skipped mode=" + mode.to_s() + " reason=work-cap cap_words=" + max_work_words.to_s()
  exit(0)

out_u = i64[capacity]
out_v = i64[capacity]
out_w = i64[capacity]
repair_meta = i64[16]
t2 = ccall("__w_clock_ms") ## i64
repaired = ffsr_try_repair(bad_u, bad_v, bad_w, rank, n, mode, max_work_words, out_u, out_v, out_w, capacity, repair_meta) ## i64
t3 = ccall("__w_clock_ms") ## i64
<< "  result mode=" + mode.to_s() + " repaired_rank=" + repaired.to_s() + " exact=" + repair_meta[8].to_s() + " edits=" + repair_meta[4].to_s() + " conflicts=" + repair_meta[6].to_s() + " basis=" + repair_meta[2].to_s() + "/" + repair_meta[1].to_s() + " reductions=" + repair_meta[3].to_s() + " solve_ms=" + (t3 - t2).to_s() + " work_words=" + repair_meta[10].to_s()
# Mode 0 deliberately admits cross-axis linearizations and may be rejected by
# the nonlinear full gate.  The exact-gate rejection is a valid benchmark
# result; axis-safe modes must repair this planted instance.
if mode != 0 && (repaired != rank || repair_meta[8] != 1)
  exit(1)
