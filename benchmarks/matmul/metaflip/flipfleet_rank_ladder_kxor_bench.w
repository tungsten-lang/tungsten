# Optional GPU closure audit for exact rank-ladder R+2 seeds.
#
# This benchmark reuses the production 6->5 through 9->8 k-XOR joins without
# changing their pool policy.  Every GPU output is reloaded, full-tensor gated,
# and passed through the ladder's reversal/origin/debt admission policy.
#
# Usage: flipfleet_rank_ladder_kxor_bench [openers] [subsets] [max-k]

use flipfleet_rank_ladder
use flipfleet_kxor_pool_lib

-> ffrlgb_arg(args, index, fallback) i64
  value = fallback ## i64
  if args.size() > index
    parsed = args[index].to_i() ## i64
    if parsed > 0
      value = parsed
  value

-> ffrlgb_run(label, path, openers, subsets, max_k, totals) (String String i64 i64 i64 i64[]) i64
  n = 4 ## i64
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  origin = i64[state_size]
  loaded = ffw_load_scheme_cap(origin, path, n, capacity, 88001, 0, 1, 1, 1) ## i64
  if loaded != 47 || ffw_verify_current_exact(origin, n) != 1
    return 0 - 1
  stats = i64[32]
  z = ffrl_stats_init(stats, loaded) ## i64
  trial = 0 ## i64
  while trial < openers
    stats[0] = stats[0] + 1
    opened = i64[state_size]
    identities = i64[18]
    meta = i64[8]
    opened_rank = ffrl_open_trial_k2(origin, trial, opened, identities, meta) ## i64
    if opened_rank == 49 && meta[3] == 2 && meta[4] == 1
      stats[1] = stats[1] + 1
      forbidden0 = i64[state_size]
      forbidden1 = i64[state_size]
      rank0 = ffrl_make_forbidden(opened, identities, 0, forbidden0, 88101 + trial * 2) ## i64
      rank1 = ffrl_make_forbidden(opened, identities, 9, forbidden1, 88102 + trial * 2) ## i64
      if rank0 == 48 && rank1 == 48
        seed_path = "/tmp/ffrl_kxor_" + label + "_" + trial.to_s() + ".txt" ## String
        dumped = ffw_dump_current(opened, seed_path) ## i64
        if dumped == 49
          k = 6 ## i64
          while k <= max_k && k <= 9
            pool = 32 ## i64
            if k >= 8
              pool = 16
            output_path = seed_path + ".k" + k.to_s() + ".out"
            stats[4] = stats[4] + 1
            stats[24] = stats[24] + 1
            hit = ffx_search(seed_path, output_path, n, k, subsets, pool, 2, trial * 53 + k, "benchmarks/matmul/metaflip/flipfleet_kxor_pool.metal") ## i64
            if hit > 0
              stats[25] = stats[25] + 1
              candidate = i64[state_size]
              candidate_rank = ffw_load_scheme_cap(candidate, output_path, n, capacity, 89001 + trial * 17 + k, 0, 1, 1, 1) ## i64
              if candidate_rank == hit && ffw_verify_current_exact(candidate, n) == 1
                admitted = ffrl_admit_candidate(origin, opened, opened, candidate, forbidden0, forbidden1, stats) ## i64
                if admitted == 1
                  stats[26] = stats[26] + 1
                  # One more nonincreasing k-XOR stage is allowed only from a
                  # genuinely admitted R+1 child.
                  second_path = output_path + ".second"
                  stats[4] = stats[4] + 1
                  stats[24] = stats[24] + 1
                  second = ffx_search(output_path, second_path, n, k, subsets, pool, 2, trial * 97 + k + 101, "benchmarks/matmul/metaflip/flipfleet_kxor_pool.metal") ## i64
                  if second > 0
                    stats[25] = stats[25] + 1
                    endpoint = i64[state_size]
                    endpoint_rank = ffw_load_scheme_cap(endpoint, second_path, n, capacity, 90001 + trial * 19 + k, 0, 1, 1, 1) ## i64
                    if endpoint_rank == second && ffw_verify_current_exact(endpoint, n) == 1
                      if ffrl_admit_candidate(origin, opened, candidate, endpoint, forbidden0, forbidden1, stats) == 1
                        stats[26] = stats[26] + 1
            k += 1
    if opened_rank != 49
      stats[2] = stats[2] + 1
    trial += 1
  i = 0 ## i64
  while i < 32
    totals[i] = totals[i] + stats[i]
    i += 1
  line = "RANK_LADDER_KXOR seed=" + label ## String
  line = line + " open=" + stats[1].to_s() + "/" + stats[0].to_s()
  line = line + " gpu_search=" + stats[24].to_s()
  line = line + " gpu_hit=" + stats[25].to_s()
  line = line + " admitted=" + stats[26].to_s()
  line = line + " inverse=" + stats[7].to_s()
  line = line + " origin_block=" + stats[8].to_s()
  line = line + " returns=" + stats[11].to_s()
  line = line + " novel=" + stats[12].to_s()
  line = line + " improve=" + stats[13].to_s()
  line = line + " exact_fail=" + stats[10].to_s()
  << line
  1

args = argv()
openers = ffrlgb_arg(args, 0, 2) ## i64
subsets = ffrlgb_arg(args, 1, 8) ## i64
max_k = ffrlgb_arg(args, 2, 9) ## i64
if max_k < 6
  max_k = 6
totals = i64[32]
first = ffrlgb_run("d450", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", openers, subsets, max_k, totals) ## i64
second = ffrlgb_run("d677", "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt", openers, subsets, max_k, totals) ## i64
recommendation = "do-not-integrate"
if totals[12] > 0
  recommendation = "seed-bank-only"
if totals[13] > 0
  recommendation = "integrate-bounded-pool"
<< "RANK_LADDER_KXOR_SUMMARY gpu_search=" + totals[24].to_s() + " gpu_hit=" + totals[25].to_s() + " admitted=" + totals[26].to_s() + " returns=" + totals[11].to_s() + " improve=" + totals[13].to_s() + " recommendation=" + recommendation
if first < 0 || second < 0
  exit(1)
