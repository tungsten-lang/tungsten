use ../lib/metaflip/kernels/pool
use ../lib/metaflip/tui

-> ffkpt_expect(label, condition)
  if condition == 0
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
count = ffkp_select_group_modes_ready(22, 7, 247, 0, 4096, ready, last_modes, pulls, rewards, selected) ## i64
z = ffkpt_expect("one strategy per pool family", count == 3 && ffkp_mode_group(selected[0]) != ffkp_mode_group(selected[1]) && ffkp_mode_group(selected[0]) != ffkp_mode_group(selected[2]) && ffkp_mode_group(selected[1]) != ffkp_mode_group(selected[2]))

# Twenty-three names leave an intentionally unpaired final TUI cell.  The
# renderer must keep that row valid without inventing a placeholder column.
last_row = ff_tui_gpu_pool_pair(ffkp_mode_name(22), 1, 1, "", 0, 0, 120)
z = ffkpt_expect("odd final TUI row", last_row.include?("dynamic-syzygy") && last_row.include?("invalid") == false)

<< "PASS heterogeneous kernel pool modes=23 groups=3"
