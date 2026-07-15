use flipfleet_rect_profiles

-> ffrpt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

labels = ["3x3x4", "3x3x5", "3x4x4", "3x4x5", "3x4x6", "3x5x5", "4x4x5", "4x5x5", "4x4x6", "4x5x6", "4x5x7", "4x6x7", "5x6x7", "2x4x5", "2x3x4", "3x4x7", "3x5x6", "3x5x7", "4x5x8", "4x6x6", "4x6x8", "2x2x5", "2x2x6", "2x3x5", "2x5x6"]
records = i64[25]
records[0] = 29
records[1] = 36
records[2] = 38
records[3] = 47
records[4] = 54
records[5] = 58
records[6] = 60
records[7] = 76
records[8] = 73
records[9] = 90
records[10] = 104
records[11] = 123
records[12] = 150
records[13] = 33
records[14] = 20
records[15] = 64
records[16] = 68
records[17] = 79
records[18] = 118
records[19] = 105
records[20] = 140
records[21] = 18
records[22] = 21
records[23] = 25
records[24] = 47
i = 0 ## i64
while i < labels.size()
  label = labels[i]
  n = ffrp_n(label) ## i64
  m = ffrp_m(label) ## i64
  p = ffrp_p(label) ## i64
  z = ffrpt_expect(label + " supported", ffrp_supported(n, m, p) == 1)
  z = ffrpt_expect(label + " round-trip", ffrp_label(n, m, p) == label)
  z = ffrpt_expect(label + " record", ffrp_record_rank(n, m, p) == records[i])
  target = records[i] - 1 ## i64
  if label == "2x3x4"
    target = records[i]
  z = ffrpt_expect(label + " target", ffrp_target_rank(n, m, p) == target)
  seed = ffrp_seed_rel(n, m, p)
  z = ffrpt_expect(label + " seed shape", seed.include?("matmul_" + label + "_rank" + records[i].to_s()))
  z = ffrpt_expect(label + " seed field", seed.ends_with?("_gf2.txt"))
  if label == "2x4x5"
    z = ffrpt_expect("245 fleet density default", seed.ends_with?("matmul_2x4x5_rank33_d222_fleet_gf2.txt"))
  if label == "3x4x6"
    z = ffrpt_expect("346 GL frontier default", seed.ends_with?("matmul_3x4x6_rank54_d488_gl_frontier_gf2.txt"))
  if label == "3x4x7"
    z = ffrpt_expect("347 GL frontier default", seed.ends_with?("matmul_3x4x7_rank64_d519_gl_frontier_gf2.txt"))
  if label == "4x4x6"
    z = ffrpt_expect("446 GL frontier default", seed.ends_with?("matmul_4x4x6_rank73_d690_gl_frontier_gf2.txt"))
  if label == "4x5x6"
    z = ffrpt_expect("456 GL frontier default", seed.ends_with?("matmul_4x5x6_rank90_d907_gl_frontier_gf2.txt"))
  if label == "4x5x7"
    z = ffrpt_expect("457 GL frontier default", seed.ends_with?("matmul_4x5x7_rank104_d1089_gl_frontier_gf2.txt"))
  if label == "3x3x5"
    z = ffrpt_expect("335 density leader default", seed.ends_with?("matmul_3x3x5_rank36_d287_gf2.txt"))
  if label == "3x5x7"
    z = ffrpt_expect("357 density leader default", seed.ends_with?("matmul_3x5x7_rank79_d699_gf2.txt"))
  if label == "4x5x8"
    z = ffrpt_expect("458 GL frontier default", seed.ends_with?("matmul_4x5x8_rank118_d1283_gl_frontier_gf2.txt"))
  if label == "4x4x5"
    z = ffrpt_expect("445 GL frontier default", seed.ends_with?("matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt"))
  if label == "4x6x6"
    z = ffrpt_expect("466 density leader default", seed.ends_with?("matmul_4x6x6_rank105_d1197_gf2.txt"))
  if label == "4x6x8"
    z = ffrpt_expect("468 GL frontier default", seed.ends_with?("matmul_4x6x8_rank140_d1560_global_isotropy_gf2.txt"))
  if label == "4x6x7"
    z = ffrpt_expect("467 GL frontier default", seed.ends_with?("matmul_4x6x7_rank123_d1406_gl_frontier_gf2.txt"))
  if label == "5x6x7"
    z = ffrpt_expect("567 GL frontier default", seed.ends_with?("matmul_5x6x7_rank150_d1875_gl_frontier_gf2.txt"))
  if label == "2x3x4"
    z = ffrpt_expect("234 density leader default", seed.ends_with?("matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt"))
  if label == "2x3x5"
    z = ffrpt_expect("235 fleet density leader default", seed.ends_with?("matmul_2x3x5_rank25_d160_fleet_gf2.txt"))
  if label == "2x5x6"
    z = ffrpt_expect("256 exact catalog default", seed.ends_with?("matmul_2x5x6_rank47_catalog_gf2.txt"))
  i += 1

z = ffrpt_expect("invalid label", ffrp_supported_label("4x5") == 0 && ffrp_n("4x5") == 0)
z = ffrpt_expect("invalid shape", ffrp_supported(5, 5, 6) == 0 && ffrp_label(5, 5, 6) == "invalid")
z = ffrpt_expect("proven optimum boundary", ffrp_proven_optimal(2,3,4) == 1 && ffrp_proven_optimal(2,3,5) == 0 && ffrp_proven_optimal(2,2,5) == 0 && ffrp_proven_optimal(2,4,5) == 0 && ffrp_proven_optimal(3,3,4) == 0)
z = ffrpt_expect("225 five-door frontier", ffrp_frontier_seed_count(2,2,5) == 5 && ffrp_frontier_seed_rel(2,2,5,0).ends_with?("matmul_2x2x5_rank18_d84_gf2.txt") && ffrp_frontier_seed_rel(2,2,5,1).ends_with?("matmul_2x2x5_rank18_d88_gf2.txt") && ffrp_frontier_seed_rel(2,2,5,2).ends_with?("matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt") && ffrp_frontier_seed_rel(2,2,5,3).ends_with?("matmul_2x2x5_rank18_d84_block_splice_gf2.txt") && ffrp_frontier_seed_rel(2,2,5,4).ends_with?("matmul_2x2x5_rank18_d84_gpu_block_tunnel_gf2.txt"))
z = ffrpt_expect("226 two-door frontier", ffrp_frontier_seed_count(2,2,6) == 2 && ffrp_frontier_seed_rel(2,2,6,0).ends_with?("matmul_2x2x6_rank21_strassen_blocks_gf2.txt") && ffrp_frontier_seed_rel(2,2,6,1).ends_with?("matmul_2x2x6_rank21_d108_block_local_gl_gf2.txt"))
z = ffrpt_expect("235 four-door frontier", ffrp_frontier_seed_count(2,3,5) == 4 && ffrp_frontier_seed_rel(2,3,5,0).ends_with?("matmul_2x3x5_rank25_d160_fleet_gf2.txt") && ffrp_frontier_seed_rel(2,3,5,1).ends_with?("matmul_2x3x5_rank25_d170_fleet_gf2.txt") && ffrp_frontier_seed_rel(2,3,5,2).ends_with?("matmul_2x3x5_rank25_d210_fleet_gf2.txt") && ffrp_frontier_seed_rel(2,3,5,3).ends_with?("matmul_2x3x5_rank25_d278_fleet_gf2.txt"))
z = ffrpt_expect("256 two-door frontier", ffrp_frontier_seed_count(2,5,6) == 2 && ffrp_frontier_seed_rel(2,5,6,0).ends_with?("matmul_2x5x6_rank47_catalog_gf2.txt") && ffrp_frontier_seed_rel(2,5,6,1).ends_with?("matmul_2x5x6_rank47_d438_orbit_door_gf2.txt"))
z = ffrpt_expect("445 three-door frontier", ffrp_frontier_seed_count(4,4,5) == 3 && ffrp_frontier_seed_rel(4,4,5,0).ends_with?("matmul_4x4x5_rank60_d628_gl_frontier_gf2.txt") && ffrp_frontier_seed_rel(4,4,5,1).ends_with?("matmul_4x4x5_rank60_d919_gf2.txt") && ffrp_frontier_seed_rel(4,4,5,2).ends_with?("matmul_4x4x5_rank60_d662_short_orbit_splice_gf2.txt"))
z = ffrpt_expect("245 three-door frontier", ffrp_frontier_seed_count(2,4,5) == 3 && ffrp_frontier_seed_rel(2,4,5,0).ends_with?("matmul_2x4x5_rank33_d222_fleet_gf2.txt") && ffrp_frontier_seed_rel(2,4,5,1).ends_with?("matmul_2x4x5_rank33_d241_gl_frontier_gf2.txt") && ffrp_frontier_seed_rel(2,4,5,2).ends_with?("matmul_2x4x5_rank33_catalog_gf2.txt"))
z = ffrpt_expect("346/347 two-door frontiers", ffrp_frontier_seed_count(3,4,6) == 2 && ffrp_frontier_seed_count(3,4,7) == 2 && ffrp_frontier_seed_rel(3,4,7,1).ends_with?("matmul_3x4x7_rank64_d576_gf2.txt"))
z = ffrpt_expect("large two-door frontiers", ffrp_frontier_seed_count(4,4,6) == 2 && ffrp_frontier_seed_count(4,5,6) == 2 && ffrp_frontier_seed_count(4,5,7) == 2 && ffrp_frontier_seed_count(4,5,8) == 2 && ffrp_frontier_seed_count(4,6,7) == 2 && ffrp_frontier_seed_count(4,6,8) == 2 && ffrp_frontier_seed_count(5,6,7) == 2)
z = ffrpt_expect("ordinary frontier singleton", ffrp_frontier_seed_count(3,4,5) == 1 && ffrp_frontier_seed_rel(3,4,5,0) == ffrp_seed_rel(3,4,5) && ffrp_frontier_seed_rel(3,4,5,1) == "")
z = ffrpt_expect("GPU profile boundary", ffrp_gpu_cap(2, 2, 5) == 64 && ffrp_gpu_cap(2, 2, 6) == 0 && ffrp_gpu_cap(2, 3, 4) == 64 && ffrp_gpu_cap(2, 3, 5) == 68 && ffrp_gpu_cap(2, 4, 5) == 80 && ffrp_gpu_cap(2, 5, 6) == 92 && ffrp_gpu_cap(3, 3, 5) == 77 && ffrp_gpu_cap(3, 4, 5) == 92 && ffrp_gpu_cap(3, 4, 6) == 0 && ffrp_gpu_cap(3, 4, 7) == 0 && ffrp_gpu_cap(3, 5, 5) == 107 && ffrp_gpu_cap(3, 5, 6) == 0 && ffrp_gpu_cap(3, 5, 7) == 0 && ffrp_gpu_cap(4, 4, 5) == 112 && ffrp_gpu_cap(4, 5, 5) == 0 && ffrp_gpu_cap(4, 4, 6) == 0 && ffrp_gpu_cap(4, 5, 6) == 0 && ffrp_gpu_cap(4, 5, 7) == 0 && ffrp_gpu_cap(4, 5, 8) == 0 && ffrp_gpu_cap(4, 6, 6) == 0 && ffrp_gpu_cap(4, 6, 7) == 0 && ffrp_gpu_cap(4, 6, 8) == 0 && ffrp_gpu_cap(5, 6, 7) == 0)

budgets = i64[3]
z = ffrpt_expect("100M campaign budget", ffrp_campaign_budgets(100000000, budgets) == 100000000)
z = ffrpt_expect("focused work budget", budgets[0] == 10000000)
z = ffrpt_expect("adaptive budget", budgets[1] == 70000000)
z = ffrpt_expect("guaranteed wander budget", budgets[2] == 20000000)
z = ffrpt_expect("campaign budget sum", budgets[0] + budgets[1] + budgets[2] == 100000000)
z = ffrpt_expect("zone quotas", ffrp_work_quota(100000000) == 10000000 && ffrp_wander_quota(100000000) == 4000000)
z = ffrpt_expect("tiny campaign remains bounded", ffrp_campaign_budgets(1, budgets) == 1 && budgets[0] + budgets[1] + budgets[2] == 1)

<< "PASS flipfleet rectangular profiles"
