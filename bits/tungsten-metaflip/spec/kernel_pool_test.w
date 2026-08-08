use ../lib/metaflip/kernels/pool
use ../lib/metaflip/tui

-> ffkpt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

z = ffkpt_expect("23 pool strategies", ffkp_mode_count() == 23) ## i64
z = ffkpt_expect("mode-locked identity", ffkp_mode_name(20) == "mode-cpals" && ffkp_mode_group(20) == 1 && ffkp_mode_kind(20) == 9)
z = ffkpt_expect("debt MITM identity", ffkp_mode_name(21) == "debt-mitm" && ffkp_mode_group(21) == 1 && ffkp_mode_kind(21) == 9)
z = ffkpt_expect("dynamic syzygy identity", ffkp_mode_name(22) == "dynamic-syzygy" && ffkp_mode_group(22) == 2 && ffkp_mode_kind(22) == 9)
z = ffkpt_expect("bounded CPU accounting", ffkp_mode_lane_budget(4096, 20) == 32 && ffkp_mode_lane_budget(4096, 21) == 32 && ffkp_mode_lane_budget(4096, 22) == 32)
z = ffkpt_expect("general exact closers eligible", ffkp_mode_eligible(20, 3, 23) == 1 && ffkp_mode_eligible(21, 6, 153) == 1)
z = ffkpt_expect("syzygy evidence gate", ffkp_mode_eligible(22, 7, 247) == 1 && ffkp_mode_eligible(22, 6, 153) == 0)

ready = i64[ffkp_mode_count()]
mode = 0 ## i64
while mode < ffkp_mode_count()
  ready[mode] = 1
  mode += 1
pulls = i64[ffkp_mode_count() * ffkp_context_count()]
rewards = i64[ffkp_mode_count() * ffkp_context_count()]
last_modes = i64[3]
last_modes[0] = 6
last_modes[1] = 3
last_modes[2] = 10
selected = i64[ffkp_parallel_slots()]
exposure = i64[ffkp_mode_count() * ffkp_context_count()]
count = ffkp_select_group_modes_ready(22, 7, 247, 0, 4096, ready, last_modes, pulls, rewards, exposure, selected) ## i64
z = ffkpt_expect("one strategy per pool family", count == 3 && ffkp_mode_group(selected[0]) != ffkp_mode_group(selected[1]) && ffkp_mode_group(selected[0]) != ffkp_mode_group(selected[2]) && ffkp_mode_group(selected[1]) != ffkp_mode_group(selected[2]))

# Adaptive exploitation and exploration are charged by actual lane time, not
# launch count.  With equal pulls and cumulative reward, the mode that spent a
# tenth of the device time must win even though its higher mode id would lose
# the old deterministic launch-count tie.
policy_ready = i64[ffkp_mode_count()]
policy_ready[4] = 1
policy_ready[7] = 1
policy_pulls = i64[ffkp_mode_count() * ffkp_context_count()]
policy_rewards = i64[ffkp_mode_count() * ffkp_context_count()]
policy_exposure = i64[ffkp_mode_count() * ffkp_context_count()]
policy_context = ffkp_context(5, 0) ## i64
mode4 = ffkp_index(4, policy_context) ## i64
mode7 = ffkp_index(7, policy_context) ## i64
policy_pulls[mode4] = 10
policy_pulls[mode7] = 10
policy_rewards[mode4] = 1000
policy_rewards[mode7] = 1000
policy_exposure[mode4] = 400
policy_exposure[mode7] = 40
policy_last = i64[ffkp_group_count()]
policy_last[2] = 10
choice = ffkp_select_group_mode_ready(5, 2, 5, 93, 0, policy_ready, policy_last, policy_pulls, policy_rewards, policy_exposure) ## i64
z = ffkpt_expect("equal reward prefers lower lane-time exposure", choice == 7)

# At equal reward rates, UCB exploration also prefers the less-exposed mode.
policy_rewards[mode4] = 4000
policy_rewards[mode7] = 400
choice = ffkp_select_group_mode_ready(5, 2, 5, 93, 0, policy_ready, policy_last, policy_pulls, policy_rewards, policy_exposure)
z = ffkpt_expect("equal rate explores lower exposure", choice == 7)

# One launch quantum is charged up front; completion rounds elapsed time up to
# 100-ms quanta and adds only the tail, avoiding double accounting.
timed_pulls = i64[ffkp_mode_count() * ffkp_context_count()]
timed_exposure = i64[ffkp_mode_count() * ffkp_context_count()]
timed_index = ffkp_record_launch(7, 5, 0, 2, timed_pulls, timed_exposure) ## i64
z = ffkpt_expect("launch charges first lane-time quantum", timed_exposure[timed_index] == 2)
z = ffkp_record_completion_exposure(7, 5, 0, 2, 250, timed_exposure)
z = ffkpt_expect("completion charges standardized lane time", timed_exposure[timed_index] == 6)

# Forced rotation remains a hard deterministic one-in-four override.
policy_last[2] = 4
choice = ffkp_select_group_mode_ready(4, 2, 5, 93, 0, policy_ready, policy_last, policy_pulls, policy_rewards, policy_exposure)
z = ffkpt_expect("forced rotation survives exposure UCB", choice == 7)

# Twenty-three names leave an intentionally unpaired final TUI cell.  The
# renderer must keep that row valid without inventing a placeholder column.
last_row = ff_tui_gpu_pool_pair(ffkp_mode_name(22), 1, 1, "", 0, 0, 120)
z = ffkpt_expect("odd final TUI row", last_row.include?("dynamic-syzygy") && last_row.include?("invalid") == false)

<< "PASS heterogeneous kernel pool modes=23 groups=3"
