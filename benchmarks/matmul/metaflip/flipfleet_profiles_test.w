use flipfleet_profiles

-> ffp_test_expect(name, condition)
  if condition == 0
    << "FAIL " + name
    exit(1)

ffp_test_expect("3x3 frontier seeds", ffp_frontier_seed_paths(3).size() == 2)
ffp_test_expect("4x4 frontier seeds", ffp_frontier_seed_paths(4).size() == 2)
ffp_test_expect("5x5 frontier seeds", ffp_frontier_seed_paths(5).size() == 6)
ffp_test_expect("6x6 frontier seeds", ffp_frontier_seed_paths(6).size() == 4)
ffp_test_expect("7x7 frontier seeds", ffp_frontier_seed_paths(7).size() == 3)
ffp_test_expect("7x7 density leader default", ffp_seed_path(7).include?("d2952_sedoglavic"))
ffp_test_expect("5x5 density leader first", ffp_frontier_seed_paths(5)[0].include?("d1155"))
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
