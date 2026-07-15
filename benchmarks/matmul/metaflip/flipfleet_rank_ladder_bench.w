# Bounded real-frontier benchmark for the exact k=2 rank-debt ladder.
#
# Usage:
#   flipfleet_rank_ladder_bench [openers] [depth] [beam] [span3] [span4]
#                               [neutral3] [shear]
#
# Each checked-in 4x4 rank-47 basin is tested twice: strict reduction only,
# then the same closing budget with one neutral span/shear layer.  The output
# is intentionally machine-readable enough to compare future controller or
# GPU-backed closure changes.

use flipfleet_rank_ladder

-> ffrlb_value(args, index, fallback) i64
  value = fallback ## i64
  if args.size() > index
    parsed = args[index].to_i() ## i64
    if parsed >= 0
      value = parsed
  value

-> ffrlb_add_stats(total, stats) (i64[] i64[]) i64
  i = 0 ## i64
  while i < 24
    if i != 21 && i != 22 && i != 23
      total[i] = total[i] + stats[i]
    i += 1
  if stats[21] < total[21] || (stats[21] == total[21] && stats[22] > total[22])
    total[21] = stats[21]
    total[22] = stats[22]
  if stats[23] > total[23]
    total[23] = stats[23]
  1

-> ffrlb_run(label, path, arm, openers, depth, beam, merge_budget, span3, span4, neutral, shear, total) (String String String i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  n = 4 ## i64
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  origin = i64[state_size]
  loaded = ffw_load_scheme_cap(origin, path, n, capacity, 81001 + openers + neutral * 17, 0, 1, 1, 1) ## i64
  if loaded != 47 || ffw_verify_current_exact(origin, n) != 1
    << "RANK_LADDER_BENCH_ERROR seed=" + label + " path=" + path
    return 0 - 1
  best = i64[state_size]
  stats = i64[32]
  started = ccall("__w_clock_ms") ## i64
  rank = ffrl_run_k2(origin, openers, depth, beam, merge_budget, span3, span4, neutral, shear, best, stats) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  valid = 1 ## i64
  if rank > 0
    if rank > loaded || ffw_verify_current_exact(best, n) != 1 || ffrl_same_state(origin, best) == 1
      valid = 0
  z = ffrlb_add_stats(total, stats) ## i64
  result_text = "none"
  if rank > 0
    result_text = rank.to_s()
  line = "RANK_LADDER seed=" + label ## String
  line = line + " arm=" + arm
  line = line + " origin=" + loaded.to_s()
  line = line + " result=" + result_text
  line = line + " valid=" + valid.to_s()
  line = line + " open=" + stats[1].to_s() + "/" + stats[0].to_s()
  line = line + " debt_reject=" + stats[2].to_s()
  line = line + " searches=" + stats[4].to_s()
  line = line + " accepted=" + stats[5].to_s()
  line = line + " inverse=" + stats[7].to_s()
  line = line + " origin_block=" + stats[8].to_s()
  line = line + " neutral=" + stats[14].to_s()
  line = line + " reducing=" + stats[15].to_s()
  line = line + " returns=" + stats[11].to_s()
  line = line + " novel=" + stats[12].to_s()
  line = line + " improve=" + stats[13].to_s()
  line = line + " best_seen=" + stats[21].to_s()
  line = line + " distance=" + stats[22].to_s()
  line = line + " exact_fail=" + stats[10].to_s()
  line = line + " ms=" + elapsed.to_s()
  << line
  if valid == 0
    return 0 - 2
  rank

args = argv()
openers = ffrlb_value(args, 0, 4) ## i64
depth = ffrlb_value(args, 1, 3) ## i64
beam = ffrlb_value(args, 2, 6) ## i64
span3 = ffrlb_value(args, 3, 6) ## i64
span4 = ffrlb_value(args, 4, 1) ## i64
neutral = ffrlb_value(args, 5, 3) ## i64
shear = ffrlb_value(args, 6, 1) ## i64
merge_budget = 32 ## i64

total = i64[32]
total[21] = 50
paths = ["benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt",
         "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt"]
labels = ["d450", "d677"]
failures = 0 ## i64
i = 0 ## i64
while i < paths.size()
  strict = ffrlb_run(labels[i], paths[i], "down", openers, depth, beam, merge_budget, span3, span4, 0, 0, total) ## i64
  mixed = ffrlb_run(labels[i], paths[i], "mixed", openers, depth, beam, merge_budget, span3, span4, neutral, shear, total) ## i64
  if strict < 0 || mixed < 0
    failures += 1
  i += 1

recommendation = "do-not-integrate"
if total[12] > 0
  recommendation = "seed-bank-only"
if total[13] > 0
  recommendation = "integrate-bounded-pool"
summary = "RANK_LADDER_SUMMARY runs=4 open=" + total[1].to_s() + "/" + total[0].to_s() ## String
summary = summary + " searches=" + total[4].to_s()
summary = summary + " accepted=" + total[5].to_s()
summary = summary + " returns=" + total[11].to_s()
summary = summary + " novel=" + total[12].to_s()
summary = summary + " improve=" + total[13].to_s()
summary = summary + " best_seen=" + total[21].to_s()
summary = summary + " recommendation=" + recommendation
<< summary
if failures > 0
  exit(1)
