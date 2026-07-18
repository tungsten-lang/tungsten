use ../lib/metaflip/seeds/catalog

failures = 0 ## i64

-> s7crpt_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL " + label
    return 1
  0

# 7x7 has no C3 frontier, so slot 9 must add a mixed/balanced door instead of
# silently duplicating the leader.  C3-capable 5x5/6x6 profiles are unchanged.
failures += s7crpt_expect("7x7 slot 9 uses mixed bank", ffp_door(7, 9) == 5)
failures += s7crpt_expect("7x7 slot 9 stays balanced", ffp_zone(9) == 1)
failures += s7crpt_expect("5x5 retains symmetry lane", ffp_door(5, 6) == 4)
failures += s7crpt_expect("6x6 retains symmetry lane", ffp_door(6, 8) == 4)

# A 64-worker GPU-backed 7x7 shard should now have no fake symmetry lane and
# one more mixed role.
counts = i64[7]
slot = 0 ## i64
while slot < 64
  counts[ffp_seed_door(ffp_door(7, slot))] = counts[ffp_seed_door(ffp_door(7, slot))] + 1
  slot += 1
failures += s7crpt_expect("wide 7x7 has no unavailable symmetry door", counts[4] == 0)
failures += s7crpt_expect("wide 7x7 mixed count", counts[5] == 15)
failures += s7crpt_expect("wide 7x7 frontier count", counts[1] == 17)
failures += s7crpt_expect("wide 7x7 near1 count", counts[2] == 15)
failures += s7crpt_expect("wide 7x7 near2 count", counts[3] == 15)

# A CPU-only shard also used to reserve one of its GPU-role mirrors for the
# unavailable C3 engine.  Filtering it before the prefix is built restores an
# ordinary shoulder lane without changing the total worker count.
failures += s7crpt_expect("7x7 CPU strategy excludes C3 role", ffp_cpu_strategy_lane_count(7) == 5)
failures += s7crpt_expect("5x5 CPU strategy retains C3 role", ffp_cpu_strategy_lane_count(5) == 6 && ffp_cpu_strategy_role_at(5, 2) == 2)
failures += s7crpt_expect("6x6 CPU strategy retains C3 role", ffp_cpu_strategy_lane_count(6) == 6 && ffp_cpu_strategy_role_at(6, 2) == 2)
cpu_counts = i64[7]
slot = 0
while slot < 64
  cpu_counts[ffp_seed_door(ffp_door_gpu(7, slot, 0))] = cpu_counts[ffp_seed_door(ffp_door_gpu(7, slot, 0))] + 1
  slot += 1
failures += s7crpt_expect("CPU-only 7x7 has no unavailable symmetry door", cpu_counts[4] == 0)
failures += s7crpt_expect("CPU-only wide leader count", cpu_counts[0] == 2)
failures += s7crpt_expect("CPU-only wide frontier count", cpu_counts[1] == 17)
failures += s7crpt_expect("CPU-only wide near1 count", cpu_counts[2] == 13)
failures += s7crpt_expect("CPU-only wide near2 count", cpu_counts[3] == 13)
failures += s7crpt_expect("CPU-only wide mixed count", cpu_counts[5] == 18)
failures += s7crpt_expect("CPU-only wide anchor count", cpu_counts[6] == 1)

if failures > 0
  << "7x7 CPU role policy: " + failures.to_s() + " failure(s)"
  exit(1)
<< "PASS 7x7 CPU role policy gpu_mixed=15 cpu_mixed=18 cpu_near1=13 cpu_near2=13"
