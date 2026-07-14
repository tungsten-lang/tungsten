# Canonical rectangular GF(2) campaign profiles.
#
# Keep this module free of worker/GPU dependencies: both the generic CPU lane
# and dimension-specialized Metal bundle consume it.  Shapes are deliberately
# allowlisted.  Although the rectangular worker is runtime-generic, admitting
# a shape here means that FlipFleet has an exact checked-in frontier seed and a
# documented strict-improvement target for it.

-> ffrp_supported(n, m, p) (i64 i64 i64) i64
  ok = 0 ## i64
  if n == 3 && m == 3 && p == 4
    ok = 1
  if n == 3 && m == 3 && p == 5
    ok = 1
  if n == 3 && m == 4 && p == 4
    ok = 1
  if n == 3 && m == 4 && p == 5
    ok = 1
  if n == 3 && m == 4 && p == 6
    ok = 1
  if n == 3 && m == 5 && p == 5
    ok = 1
  if n == 4 && m == 4 && p == 5
    ok = 1
  if n == 4 && m == 5 && p == 5
    ok = 1
  if n == 4 && m == 4 && p == 6
    ok = 1
  if n == 4 && m == 5 && p == 6
    ok = 1
  if n == 4 && m == 5 && p == 7
    ok = 1
  ok

-> ffrp_supported_label(label) (String) i64
  ok = 0 ## i64
  if label == "3x3x4" || label == "3x3x5" || label == "3x4x4" || label == "3x4x5" || label == "3x4x6" || label == "3x5x5" || label == "4x4x5" || label == "4x5x5" || label == "4x4x6" || label == "4x5x6" || label == "4x5x7"
    ok = 1
  ok

-> ffrp_n(label) (String) i64
  if ffrp_supported_label(label) == 1
    return label.split("x")[0].to_i()
  0

-> ffrp_m(label) (String) i64
  if ffrp_supported_label(label) == 1
    return label.split("x")[1].to_i()
  0

-> ffrp_p(label) (String) i64
  if ffrp_supported_label(label) == 1
    return label.split("x")[2].to_i()
  0

-> ffrp_label(n, m, p) (i64 i64 i64)
  if ffrp_supported(n, m, p) == 1
    return n.to_s() + "x" + m.to_s() + "x" + p.to_s()
  "invalid"

-> ffrp_record_rank(n, m, p) (i64 i64 i64) i64
  if n == 3 && m == 3 && p == 4
    return 29
  if n == 3 && m == 3 && p == 5
    return 36
  if n == 3 && m == 4 && p == 4
    return 38
  if n == 3 && m == 4 && p == 5
    return 47
  if n == 3 && m == 4 && p == 6
    return 54
  if n == 3 && m == 5 && p == 5
    return 58
  if n == 4 && m == 4 && p == 5
    return 60
  if n == 4 && m == 5 && p == 5
    return 76
  if n == 4 && m == 4 && p == 6
    return 73
  if n == 4 && m == 5 && p == 6
    return 90
  if n == 4 && m == 5 && p == 7
    return 104
  0

-> ffrp_target_rank(n, m, p) (i64 i64 i64) i64
  record = ffrp_record_rank(n, m, p) ## i64
  if record > 0
    return record - 1
  0

-> ffrp_seed_rel(n, m, p) (i64 i64 i64)
  base = "benchmarks/matmul/metaflip/"
  if n == 3 && m == 3 && p == 4
    return base + "matmul_3x3x4_rank29_gf2.txt"
  if n == 3 && m == 3 && p == 5
    return base + "matmul_3x3x5_rank36_d287_gf2.txt"
  if n == 3 && m == 4 && p == 4
    return base + "matmul_3x4x4_rank38_gf2.txt"
  if n == 3 && m == 4 && p == 5
    return base + "matmul_3x4x5_rank47_d386_gf2.txt"
  if n == 3 && m == 4 && p == 6
    return base + "matmul_3x4x6_rank54_catalog_gf2.txt"
  if n == 3 && m == 5 && p == 5
    return base + "matmul_3x5x5_rank58_d518_gf2.txt"
  if n == 4 && m == 4 && p == 5
    return base + "matmul_4x4x5_rank60_d919_gf2.txt"
  if n == 4 && m == 5 && p == 5
    return base + "matmul_4x5x5_rank76_gf2.txt"
  if n == 4 && m == 4 && p == 6
    return base + "matmul_4x4x6_rank73_gf2.txt"
  if n == 4 && m == 5 && p == 6
    return base + "matmul_4x5x6_rank90_catalog_gf2.txt"
  if n == 4 && m == 5 && p == 7
    return base + "matmul_4x5x7_rank104_d1160_gf2.txt"
  ""

# GPU geometry is intentionally present only for profiles with a checked-in,
# dimension-specialized Metal source.  The five larger profiles remain valid
# CPU campaigns without pretending that a generic square kernel is safe.
-> ffrp_gpu_cap(n, m, p) (i64 i64 i64) i64
  if n == 3 && m == 3 && p == 4
    return 68
  if n == 3 && m == 3 && p == 5
    return 77
  if n == 3 && m == 4 && p == 4
    return 80
  if n == 3 && m == 4 && p == 5
    return 92
  if n == 3 && m == 5 && p == 5
    return 107
  if n == 4 && m == 4 && p == 5
    return 112
  0

-> ffrp_gpu_wpg(n, m, p) (i64 i64 i64) i64
  if ffrp_gpu_cap(n, m, p) > 0
    return 16
  0

# A finite standalone campaign must not depend on the RNG-selected starting
# band to see both sides of the search.  Reserve deterministic bookends for
# focused work and algebraic wandering, and leave most moves to the adaptive
# sawtooth zone engine.  At the documented 100M-move scale this is
# 10M work + 70M adaptive + 20M wander; a 10k smoke is already long enough
# for the guaranteed wander slice to hit the worker's 2k split cadence.
-> ffrp_campaign_budgets(steps, budgets) (i64 i64[]) i64
  total = steps ## i64
  if total < 0
    total = 0
  focused_work = total / 10 ## i64
  guaranteed_wander = total / 5 ## i64
  if total >= 2 && focused_work < 1
    focused_work = 1
  if total >= 2 && guaranteed_wander < 1
    guaranteed_wander = 1
  if focused_work + guaranteed_wander > total
    guaranteed_wander = total - focused_work
  adaptive = total - focused_work - guaranteed_wander ## i64
  budgets[0] = focused_work
  budgets[1] = adaptive
  budgets[2] = guaranteed_wander
  total

-> ffrp_work_quota(steps) (i64) i64
  quota = steps / 10 ## i64
  if quota < 1000
    quota = 1000
  quota

-> ffrp_wander_quota(steps) (i64) i64
  quota = steps / 25 ## i64
  if quota < 250
    quota = 250
  quota
