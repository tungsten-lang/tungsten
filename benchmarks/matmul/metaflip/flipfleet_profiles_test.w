use flipfleet_profiles

-> ffp_test_expect(name, condition) (String bool) i64
  if !condition
    << "FAIL " + name
    exit(1)
  1

ffp_test_expect("2x2 record is Strassen-7", ffp_record(2) == 7 && ffp_record_known(2) == 1)
ffp_test_expect("2x2 seed is Strassen gf2", ffp_seed_path(2).include?("matmul_2x2_rank7_strassen_gf2"))
ffp_test_expect("2x2 frontier seeds", ffp_frontier_seed_paths(2).size() == 9)
ffp_test_expect("2x2 GL doors present", ffp_frontier_seed_paths(2)[1].include?("d36_gl120") && ffp_frontier_seed_paths(2)[8].include?("d42_gl207"))
ffp_test_expect("3x3 frontier seeds", ffp_frontier_seed_paths(3).size() == 2)
ffp_test_expect("4x4 frontier seeds", ffp_frontier_seed_paths(4).size() == 2)
ffp_test_expect("5x5 frontier seeds", ffp_frontier_seed_paths(5).size() == 12)
ffp_test_expect("6x6 frontier seeds", ffp_frontier_seed_paths(6).size() == 12)
ffp_test_expect("7x7 frontier seeds", ffp_frontier_seed_paths(7).size() == 14)
ffp_test_expect("7x7 rank247 default", ffp_record(7) == 247 && ffp_seed_path(7).include?("rank247_d3098"))
ffp_test_expect("5x5 density leader first", ffp_frontier_seed_paths(5)[0].include?("d967_four_split"))
ffp_test_expect("6x6 density leader first", ffp_frontier_seed_paths(6)[0].include?("d1860_global"))
ffp_test_expect("7x7 density leader first", ffp_frontier_seed_paths(7)[0].include?("d3098_global"))
ffp_test_expect("7x7 beam doors use dense root and promoted far child", ffp_frontier_seed_paths(7)[4].include?("beam_dense") && ffp_frontier_seed_paths(7)[5].include?("d3096_partial_auto_beam_far_cuda_epoch1849"))
ffp_test_expect("7x7 affine-code door uses promoted child", ffp_frontier_seed_paths(7)[13].include?("d3096_affine_code_cuda_epoch3306"))
legacy_parent_active = 0 ## i64
seven_paths = ffp_frontier_seed_paths(7)
i = 0 ## i64
while i < seven_paths.size()
  if seven_paths[i].ends_with?("matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt") || seven_paths[i].ends_with?("matmul_7x7_rank247_d3098_affine_code_gf2.txt")
    legacy_parent_active = 1
  i += 1
ffp_test_expect("7x7 dominated provenance parents inactive", legacy_parent_active == 0)
ffp_test_expect("4x4 signed +2 shoulder", ffp_near_seed_paths(4, 2).size() == 1 && ffp_near_seed_paths(4, 2)[0].include?("rank49_d432_signed"))
ffp_test_expect("signed shoulder delta gate", ffp_near_seed_paths(4, 1).size() == 0 && ffp_near_seed_paths(5, 2).size() == 0)
ffp_test_expect("5x5 catalog doors", ffp_frontier_seed_paths(5)[8].include?("kauers_a") && ffp_frontier_seed_paths(5)[9].include?("kauers_b") && ffp_frontier_seed_paths(5)[10].include?("perminov"))
ffp_test_expect("6x6 odd-parent low-cadence doors", ffp_frontier_seed_paths(6)[8].include?("odd_parent3") && ffp_frontier_seed_paths(6)[11].include?("odd_parent5_novel"))
ffp_test_expect("7x7 odd-parent low-cadence door", ffp_frontier_seed_paths(7)[12].include?("odd_parent3"))
ffp_test_expect("mixed host reserve", ffp_default_cpu_walkers(18, 1) == 14)
ffp_test_expect("cpu-only same reserve", ffp_default_cpu_walkers(18, 0) == 14)
ffp_test_expect("small host clamp", ffp_default_cpu_walkers(4, 1) == 2)
ffp_test_expect("extra workers add frontier breadth", ffp_door(5, 12) == 1 && ffp_zone(12) == 0)
ffp_test_expect("extra workers add mixed breadth", ffp_door(5, 13) == 5 && ffp_zone(13) == 1)
ffp_test_expect("4x4 default has direct frontier", ffp_door(4, 5) == 1)
ffp_test_expect("5x5 strategy lanes clamped", ffp_cpu_strategy_lane_count(5) >= 4 && ffp_cpu_strategy_lane_count(5) <= 10)
ffp_test_expect("strategy pool is 4", ffp_cpu_strategy_pool_count() == 4)
ffp_test_expect("no-gpu first door is strategy", ffp_door_gpu(5, 0, 0) >= 100)
ffp_test_expect("no-gpu pool door", ffp_door_gpu(5, ffp_cpu_strategy_lane_count(5), 0) == ffp_cpu_strategy_door(10))
ffp_test_expect("strategy seed map rank", ffp_strategy_seed_door(0) == 3)
ffp_test_expect("strategy seed map novelty", ffp_strategy_seed_door(8) == 1)

<< "flipfleet_profiles_test: all checks passed"
