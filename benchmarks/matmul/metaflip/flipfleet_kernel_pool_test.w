use metaflip_worker
use flipfleet_kernel_pool
use flipfleet_map_elites
use flipfleet_rank_debt

-> kp_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

z = kp_expect("mode count", ffkp_mode_count() == 18) ## i64
z = kp_expect("group count", ffkp_group_count() == 3)
z = kp_expect("parallel child slots", ffkp_parallel_slots() == 3)
z = kp_expect("constraint group", ffkp_mode_group(0) == 0 && ffkp_mode_group(5) == 0 && ffkp_mode_group(6) == 0)
z = kp_expect("surgery group", ffkp_mode_group(1) == 1 && ffkp_mode_group(2) == 1 && ffkp_mode_group(3) == 1 && ffkp_mode_group(12) == 1 && ffkp_mode_group(13) == 1 && ffkp_mode_group(14) == 1 && ffkp_mode_group(15) == 1 && ffkp_mode_group(16) == 1 && ffkp_mode_group(17) == 1)
z = kp_expect("escape group", ffkp_mode_group(4) == 2 && ffkp_mode_group(7) == 2 && ffkp_mode_group(8) == 2 && ffkp_mode_group(9) == 2 && ffkp_mode_group(10) == 2 && ffkp_mode_group(11) == 2)
z = kp_expect("invalid group", ffkp_mode_group(18) == -1)
z = kp_expect("new names", ffkp_mode_name(10) == "beam-recipes" && ffkp_mode_name(11) == "primitive-5plus" && ffkp_mode_name(12) == "parent-diff" && ffkp_mode_name(13) == "xor-8to7" && ffkp_mode_name(14) == "xor-9to8" && ffkp_mode_name(15) == "span-refactor-3" && ffkp_mode_name(16) == "span-refactor-4" && ffkp_mode_name(17) == "low-rank-shear")
z = kp_expect("new kinds", ffkp_mode_kind(11) == 2 && ffkp_mode_kind(12) == 4 && ffkp_mode_kind(13) == 2 && ffkp_mode_kind(14) == 2 && ffkp_mode_kind(15) == 5 && ffkp_mode_kind(16) == 5 && ffkp_mode_kind(17) == 6)
z = kp_expect("budget small quantum", ffkp_lane_budget(64) == 32)
z = kp_expect("budget three eighths", ffkp_lane_budget(4096) == 1536)
z = kp_expect("budget cap", ffkp_lane_budget(65536) == 1536)
z = kp_expect("mitm saturation cap", ffkp_mode_lane_budget(4096, 1) == 512)
z = kp_expect("kxor saturation cap", ffkp_mode_lane_budget(4096, 2) == 256)
z = kp_expect("circuit saturation cap", ffkp_mode_lane_budget(4096, 11) == 256)
z = kp_expect("single CPU differential cap", ffkp_mode_lane_budget(4096, 12) == 32)
z = kp_expect("large-k saturation cap", ffkp_mode_lane_budget(4096, 13) == 128 && ffkp_mode_lane_budget(4096, 14) == 128)
z = kp_expect("large-k rank eligibility", ffkp_mode_eligible(13, 5, 7) == 0 && ffkp_mode_eligible(13, 5, 8) == 1 && ffkp_mode_eligible(14, 5, 8) == 0 && ffkp_mode_eligible(14, 5, 9) == 1)
z = kp_expect("span saturation caps", ffkp_mode_lane_budget(4096, 15) == 256 && ffkp_mode_lane_budget(4096, 16) == 128)
z = kp_expect("span rank eligibility", ffkp_mode_eligible(15, 5, 2) == 0 && ffkp_mode_eligible(15, 5, 3) == 1 && ffkp_mode_eligible(16, 5, 3) == 0 && ffkp_mode_eligible(16, 5, 4) == 1)
z = kp_expect("shear evidence eligibility", ffkp_mode_eligible(17, 4, 47) == 0 && ffkp_mode_eligible(17, 5, 93) == 1 && ffkp_mode_eligible(17, 7, 250) == 1)
z = kp_expect("shear tensor caps", ffkp_mode_lane_budget_for_tensor(5, 4096, 17) == 256 && ffkp_mode_lane_budget_for_tensor(6, 4096, 17) == 128)
beam_cap = ffw_default_capacity(3) ## i64
beam_size = ffw_state_size(beam_cap) ## i64
beam_source = i64[beam_size]
beam_source_rank = ffw_init_naive_cap(beam_source, 3, beam_cap, 731, 4, 2, 1000, 250) ## i64
beam_seed = ffkp_beam_recipe_state(beam_source, 3, beam_cap, beam_size, 9, 4, 2, 1000, 250)
z = kp_expect("beam recipe seed exact", beam_source_rank == 27 && beam_seed != nil && ffw_verify_best_exact(beam_seed, 3) == 1)
z = kp_expect("beam recipe bounded debt", beam_seed != nil && ffw_best_rank(beam_seed) > 27 && ffw_best_rank(beam_seed) <= 31)
cap0 = ffkp_mode_lane_budget_for_tensor(4, 4096, 0) ## i64
z = kp_expect("4x4 constraint evidence cap", cap0 == 128)

scalable_modes = i64[3]
scalable_modes[0] = 0
scalable_modes[1] = 4
scalable_modes[2] = 7
scalable_lanes = i64[3]
scalable_reserved = ffkp_allocate_selected_lanes(4096, scalable_modes, 3, scalable_lanes) ## i64
z = kp_expect("three scalable reserve", scalable_reserved == 1536)
z = kp_expect("three scalable fair", scalable_lanes[0] == 512 && scalable_lanes[1] == 512 && scalable_lanes[2] == 512)

mixed_modes = i64[3]
mixed_modes[0] = 4
mixed_modes[1] = 1
mixed_modes[2] = 2
mixed_lanes = i64[3]
mixed_reserved = ffkp_allocate_selected_lanes(4096, mixed_modes, 3, mixed_lanes) ## i64
z = kp_expect("mixed capped reserve", mixed_reserved == 1536)
z = kp_expect("mixed capped split", mixed_lanes[0] == 768 && mixed_lanes[1] == 512 && mixed_lanes[2] == 256)

join_modes = i64[3]
join_modes[0] = 1
join_modes[1] = 2
join_modes[2] = 3
join_lanes = i64[3]
join_reserved = ffkp_allocate_selected_lanes(4096, join_modes, 3, join_lanes) ## i64
z = kp_expect("all joins return slack", join_reserved == 1024)
z = kp_expect("all joins respect caps", join_lanes[0] == 512 && join_lanes[1] == 256 && join_lanes[2] == 256)

cpu_mix_modes = i64[3]
cpu_mix_modes[0] = 0
cpu_mix_modes[1] = 12
cpu_mix_modes[2] = 4
cpu_mix_lanes = i64[3]
cpu_mix_reserved = ffkp_allocate_selected_lanes(4096, cpu_mix_modes, 3, cpu_mix_lanes) ## i64
z = kp_expect("parent differential stays one quantum", cpu_mix_reserved == 1536 && cpu_mix_lanes[1] == 32)
z = kp_expect("parent differential returns width to GPU", cpu_mix_lanes[0] + cpu_mix_lanes[2] == 1504)

# At the default 4x4 width, all three families retain nonzero coverage.  The
# zero-yield constraint family stops after four SIMDgroups, exact surgery gets
# its measured saturation budget, and generic escape receives the remainder.
four_modes = i64[3]
four_modes[0] = 0
four_modes[1] = 1
four_modes[2] = 4
four_lanes = i64[3]
four_reserved = ffkp_allocate_selected_lanes_for_tensor(4, 4096, four_modes, 3, four_lanes) ## i64
z = kp_expect("4x4 evidence split reserve", four_reserved == 1536)
z = kp_expect("4x4 evidence split lanes", four_lanes[0] == 128 && four_lanes[1] == 512 && four_lanes[2] == 896)

four_kxor_modes = i64[3]
four_kxor_modes[0] = 0
four_kxor_modes[1] = 2
four_kxor_modes[2] = 4
four_kxor_lanes = i64[3]
four_kxor_reserved = ffkp_allocate_selected_lanes_for_tensor(4, 4096, four_kxor_modes, 3, four_kxor_lanes) ## i64
z = kp_expect("4x4 kxor split reserve", four_kxor_reserved == 1536)
z = kp_expect("4x4 kxor split lanes", four_kxor_lanes[0] == 128 && four_kxor_lanes[1] == 256 && four_kxor_lanes[2] == 1152)

four_span3_modes = i64[3]
four_span3_modes[0] = 0
four_span3_modes[1] = 15
four_span3_modes[2] = 4
four_span3_lanes = i64[3]
four_span3_reserved = ffkp_allocate_selected_lanes_for_tensor(4, 4096, four_span3_modes, 3, four_span3_lanes) ## i64
z = kp_expect("4x4 span3 split reserve", four_span3_reserved == 1536)
z = kp_expect("4x4 span3 split lanes", four_span3_lanes[0] == 128 && four_span3_lanes[1] == 256 && four_span3_lanes[2] == 1152)

four_span4_modes = i64[3]
four_span4_modes[0] = 0
four_span4_modes[1] = 16
four_span4_modes[2] = 4
four_span4_lanes = i64[3]
four_span4_reserved = ffkp_allocate_selected_lanes_for_tensor(4, 4096, four_span4_modes, 3, four_span4_lanes) ## i64
z = kp_expect("4x4 span4 split reserve", four_span4_reserved == 1536)
z = kp_expect("4x4 span4 split lanes", four_span4_lanes[0] == 128 && four_span4_lanes[1] == 128 && four_span4_lanes[2] == 1280)

four_floor_lanes = i64[3]
four_floor_reserved = ffkp_allocate_selected_lanes_for_tensor(4, 256, four_modes, 3, four_floor_lanes) ## i64
z = kp_expect("4x4 small-device floors", four_floor_reserved == 96 && four_floor_lanes[0] == 32 && four_floor_lanes[1] == 32 && four_floor_lanes[2] == 32)

z = kp_expect("context low", ffkp_context(3, 0) == 0)
z = kp_expect("context high", ffkp_context(7, 9) == 19)
pool_eligible = i64[11]
pool_weights = i64[11]
z = ffg_fill_profile(5, 1, pool_eligible, pool_weights)
pool_allocation = i64[11]
z = ffg_initial_allocate_pool(4096, ffkp_lane_budget(4096), pool_eligible, pool_weights, pool_allocation)
z = kp_expect("pool reserved", pool_allocation[10] == 1536)
z = kp_expect("pool total", ffg_lane_sum(pool_allocation) == 4096)

slots = ffkp_mode_count() * ffkp_context_count() ## i64
pulls = i64[slots]
rewards = i64[slots]
exposure = i64[slots]
seen = i64[ffkp_mode_count()]
epoch = 0 ## i64
last = ffkp_mode_count() - 1 ## i64
while epoch < ffkp_mode_count()
  mode = ffkp_select_mode(epoch, last, 5, 93, 0, pulls, rewards) ## i64
  seen[mode] = 1
  z = ffkp_record_launch(mode, 5, 0, 4, pulls, exposure)
  last = mode
  epoch += 1
mode = 0
while mode < ffkp_mode_count()
  z = kp_expect("cold rotation " + mode.to_s(), seen[mode] == 1)
  mode += 1

# Each batch selects at most one child from every complementary kernel group.
batch_ready = i64[ffkp_mode_count()]
batch_pulls = i64[slots]
batch_rewards = i64[slots]
batch_exposure = i64[slots]
batch_seen = i64[ffkp_mode_count()]
mode = 0
while mode < ffkp_mode_count()
  batch_ready[mode] = 1
  mode += 1
batch_modes = i64[3]
batch_epoch = 0 ## i64
batch_last_modes = i64[ffkp_group_count()]
group = 0 ## i64
while group < ffkp_group_count()
  batch_last_modes[group] = 0 - 1
  group += 1
while batch_epoch < 9
  batch_count = ffkp_select_group_modes_ready(batch_epoch, 5, 93, 0, 4096, batch_ready, batch_last_modes, batch_pulls, batch_rewards, batch_modes) ## i64
  z = kp_expect("batch fills three", batch_count == 3)
  batch_groups = i64[ffkp_group_count()]
  child = 0 ## i64
  while child < batch_count
    earlier = 0 ## i64
    while earlier < child
      z = kp_expect("batch modes distinct", batch_modes[child] != batch_modes[earlier])
      earlier += 1
    chosen = batch_modes[child] ## i64
    chosen_group = ffkp_mode_group(chosen) ## i64
    z = kp_expect("one child per group", batch_groups[chosen_group] == 0)
    batch_groups[chosen_group] = 1
    batch_seen[chosen] = batch_seen[chosen] + 1
    z = ffkp_record_launch(chosen, 5, 0, 1, batch_pulls, batch_exposure)
    batch_last_modes[chosen_group] = chosen
    child += 1
  group = 0
  while group < ffkp_group_count()
    z = kp_expect("all groups represented", batch_groups[group] == 1)
    group += 1
  batch_epoch += 1
mode = 0
while mode < ffkp_mode_count()
  z = kp_expect("batched cold coverage " + mode.to_s(), batch_seen[mode] >= 1)
  mode += 1

# A small aggregate budget admits only one complete child SIMDgroup.
small_modes = i64[3]
small_last_modes = i64[ffkp_group_count()]
group = 0
while group < ffkp_group_count()
  small_last_modes[group] = 0 - 1
  group += 1
small_count = ffkp_select_group_modes_ready(0, 5, 93, 0, 64, batch_ready, small_last_modes, pulls, rewards, small_modes) ## i64
z = kp_expect("small budget one child", small_count == 1 && small_modes[0] == 0 && small_modes[1] == -1)

# Readiness may reduce a large device below the three-child maximum.
sparse_ready = i64[ffkp_mode_count()]
sparse_ready[2] = 1
sparse_ready[7] = 1
sparse_modes = i64[3]
sparse_count = ffkp_select_group_modes_ready(0, 5, 93, 0, 4096, sparse_ready, small_last_modes, pulls, rewards, sparse_modes) ## i64
z = kp_expect("readiness limits children", sparse_count == 2)
z = kp_expect("readiness groups distinct", ffkp_mode_group(sparse_modes[0]) != ffkp_mode_group(sparse_modes[1]) && sparse_modes[2] == -1)

# One family can be refilled independently while siblings remain in flight.
single_pulls = i64[slots]
single_rewards = i64[slots]
single_last_modes = i64[ffkp_group_count()]
group = 0
while group < ffkp_group_count()
  single_last_modes[group] = 0 - 1
  group += 1
single_constraint = ffkp_select_group_mode_ready(0, 0, 5, 93, 0, batch_ready, single_last_modes, single_pulls, single_rewards) ## i64
single_surgery = ffkp_select_group_mode_ready(0, 1, 5, 93, 0, batch_ready, single_last_modes, single_pulls, single_rewards) ## i64
single_escape = ffkp_select_group_mode_ready(0, 2, 5, 93, 0, batch_ready, single_last_modes, single_pulls, single_rewards) ## i64
z = kp_expect("single group cold constraint", single_constraint == 0)
z = kp_expect("single group cold surgery", single_surgery == 1)
z = kp_expect("single group cold escape", single_escape == 4)
z = kp_expect("single group unavailable", ffkp_select_group_mode_ready(0, 0, 5, 93, 0, sparse_ready, single_last_modes, single_pulls, single_rewards) == -1)
z = kp_expect("single group invalid", ffkp_select_group_mode_ready(0, 3, 5, 93, 0, batch_ready, single_last_modes, single_pulls, single_rewards) == -1)

# Warm batches retain scalar UCB preference but cannot clone the winner into
# all three slots.  A forced-rotation ordinal still leads with the successor
# of the last launched mode.
warm_pulls = i64[slots]
warm_rewards = i64[slots]
warm_context = ffkp_context(5, 0) ## i64
mode = 0
while mode < ffkp_mode_count()
  warm_pulls[ffkp_index(mode, warm_context)] = 100
  mode += 1
warm_rewards[ffkp_index(4, warm_context)] = 1000000
single_warm_constraint = ffkp_select_group_mode_ready(5, 0, 5, 93, 0, batch_ready, single_last_modes, warm_pulls, warm_rewards) ## i64
z = kp_expect("single group excludes foreign UCB winner", ffkp_mode_group(single_warm_constraint) == 0)
warm_modes = i64[3]
warm_count = ffkp_select_group_modes_ready(5, 5, 93, 0, 4096, batch_ready, small_last_modes, warm_pulls, warm_rewards, warm_modes) ## i64
z = kp_expect("warm batch fills", warm_count == 3)
z = kp_expect("warm UCB winner", warm_modes[0] == 4)
z = kp_expect("warm one per group", ffkp_mode_group(warm_modes[0]) != ffkp_mode_group(warm_modes[1]) && ffkp_mode_group(warm_modes[0]) != ffkp_mode_group(warm_modes[2]) && ffkp_mode_group(warm_modes[1]) != ffkp_mode_group(warm_modes[2]))
rotation_modes = i64[3]
rotation_last_modes = i64[ffkp_group_count()]
rotation_last_modes[0] = 0
rotation_last_modes[1] = 1
rotation_last_modes[2] = 4
single_rotation = ffkp_select_group_mode_ready(4, 1, 5, 93, 0, batch_ready, rotation_last_modes, warm_pulls, warm_rewards) ## i64
z = kp_expect("single group forced rotation", single_rotation == 2)
rotation_count = ffkp_select_group_modes_ready(4, 5, 93, 0, 4096, batch_ready, rotation_last_modes, warm_pulls, warm_rewards, rotation_modes) ## i64
z = kp_expect("batched forced rotation", rotation_count == 3 && rotation_modes[0] == 2)
z = kp_expect("rotated group order", ffkp_mode_group(rotation_modes[0]) == 1 && ffkp_mode_group(rotation_modes[1]) == 2 && ffkp_mode_group(rotation_modes[2]) == 0)

cap = ffw_default_capacity(3) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
rank = ffw_init_naive_cap(base, 3, cap, 17, 4, 2, 1000, 250) ## i64
z = kp_expect("naive exact", rank == 27 && ffw_verify_best_exact(base, 3) == 1)
lifted = ffkp_lifted_state(base, 3, cap, size, 5, 4, 2, 1000, 250)
z = kp_expect("lift exists", lifted != nil)
z = kp_expect("lift exact", ffw_verify_best_exact(lifted, 3) == 1)
z = kp_expect("lift changes rank", ffw_best_rank(lifted) > ffw_best_rank(base))

fringe = i64[size]
z = ffw_reseed_from(fringe, base, 91)
core_u = i64[19]
core_v = i64[19]
core_w = i64[19]
i = 0
while i < 19
  core_u[i] = fringe[fringe[44] + i]
  core_v[i] = fringe[fringe[45] + i]
  core_w[i] = fringe[fringe[46] + i]
  i += 1
z = ffw_walk_fringe(fringe, 1000, 19)
i = 0
while i < 19
  z = kp_expect("fringe core u " + i.to_s(), fringe[fringe[44] + i] == core_u[i])
  z = kp_expect("fringe core v " + i.to_s(), fringe[fringe[45] + i] == core_v[i])
  z = kp_expect("fringe core w " + i.to_s(), fringe[fringe[46] + i] == core_w[i])
  i += 1
z = kp_expect("fringe exact", ffw_verify_current_exact(fringe, 3) == 1)

elites = []
keys = []
uses = []
sources = []
z = kp_expect("elite add", ffme_add(elites, keys, uses, sources, base, 27, 3, 8, 0) == 1)
z = kp_expect("elite duplicate niche", ffme_add(elites, keys, uses, sources, base, 27, 3, 8, 1) == 0)
z = kp_expect("elite lifted", ffme_add(elites, keys, uses, sources, lifted, 27, 3, 8, 2) >= 1)
picked = ffme_select(elites, uses, 0) ## i64
z = kp_expect("elite select", picked >= 0 && uses[picked] == 1)

# Copy admission must detach MAP storage from a coordinator/GPU scratch state
# that is overwritten as soon as the epoch result has been consumed.
copy_source = i64[size]
z = ffw_reseed_from(copy_source, base, 31337)
copy_elites = []
copy_keys = []
copy_uses = []
copy_sources = []
z = kp_expect("elite copy add", ffme_add_copy(copy_elites, copy_keys, copy_uses, copy_sources, copy_source, 27, 3, 8, 7, size, 41) == 1)
stored_u0 = copy_elites[0][copy_elites[0][44]] ## i64
copy_source[copy_source[44]] = copy_source[copy_source[44]] ^ 1
z = kp_expect("elite copy detached", copy_elites[0][copy_elites[0][44]] == stored_u0)
z = kp_expect("elite copy stays exact", ffw_verify_best_exact(copy_elites[0], 3) == 1)

launches = i64[4]
returns = i64[4]
failures = i64[4]
debt_exposure = i64[4]
i = 0 ## i64
while i < 8
  z = ffrd_launch(2, launches)
  z = ffrd_finish(2, 0, 100, returns, failures, debt_exposure)
  i += 1
z = kp_expect("debt shortens", ffrd_budget(1000, 2, returns, failures) == 500)
i = 0
while i < 9
  z = ffrd_finish(1, 1, 100, returns, failures, debt_exposure)
  i += 1
z = kp_expect("debt deepens", ffrd_budget(1000, 1, returns, failures) == 1500)

<< "flipfleet_kernel_pool_test: all checks passed"
