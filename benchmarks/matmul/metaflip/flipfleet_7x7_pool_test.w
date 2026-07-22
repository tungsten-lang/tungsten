use flipfleet_7x7_pool

failures = 0 ## i64

-> ff7t_expect(label, condition) i64
  if condition == false || condition == 0
    << "FAIL " + label
    return 1
  0

-> ff7t_sum(values) (i64[]) i64
  total = 0 ## i64
  i = 0 ## i64
  while i < values.size()
    total += values[i]
    i += 1
  total

# Component reservations and generic children share, rather than exceed, the
# existing logical role-10 reserve.
total_lanes = 4096 ## i64
pool_budget = ffkp_lane_budget(total_lanes) ## i64
failures += ff7t_expect("corrupt checkpoint quarantine path", ff7_corrupt_checkpoint_path("flipfleet_3x3x4_best.txt", "run-17") == "flipfleet_3x3x4_best.txt.corrupt.run-17")
quarantine_tag = "ff7t-" + ccall("__w_clock_ms").to_s()
quarantine_path = "/tmp/flipfleet_rect_checkpoint_" + quarantine_tag
quarantine_copy = ff7_corrupt_checkpoint_path(quarantine_path, quarantine_tag)
malformed_body = "malformed rectangular checkpoint\n"
quarantine_written = write_file(quarantine_path, malformed_body)
quarantine_ok = ff7_quarantine_corrupt_checkpoint(quarantine_path, quarantine_tag) ## i64
failures += ff7t_expect("corrupt checkpoint atomically removed", quarantine_written && quarantine_ok == 1 && read_file(quarantine_path) == nil)
failures += ff7t_expect("corrupt checkpoint bytes preserved", read_file(quarantine_copy) == malformed_body)
z = system("rm -f " + quarantine_path + " " + quarantine_copy)
ready = i64[2]
ready[0] = 1
ready[1] = 1
exposure = i64[2]
rewards = i64[2]
rect = i64[2]
rect_used = ff7_rect_pool_allocation(pool_budget, 0, ready, exposure, rewards, rect) ## i64
failures += ff7t_expect("rect cold reserve", rect_used == 512 && rect[0] == 256 && rect[1] == 256)

selected = i64[3]
selected[0] = 0
selected[1] = 1
selected[2] = 4
generic = i64[3]
generic_used = ff7_allocate_pool_remainder(total_lanes, pool_budget - rect_used, selected, 3, generic) ## i64
failures += ff7t_expect("pool conservation", rect_used + generic_used == pool_budget && ff7t_sum(rect) + ff7t_sum(generic) == pool_budget)
failures += ff7t_expect("pool quantized", rect[0] % 32 == 0 && rect[1] % 32 == 0 && generic[0] % 32 == 0 && generic[1] % 32 == 0 && generic[2] % 32 == 0)

# Reward/exposure shifts the fixed component slice but cannot change its sum or
# starve the colder component's SIMDgroup floor.
exposure[0] = 10
exposure[1] = 1000
rewards[0] = 10000
rewards[1] = 1
warm_used = ff7_rect_pool_allocation(pool_budget, 1, ready, exposure, rewards, rect) ## i64
failures += ff7t_expect("rect adaptive split conserved", warm_used == 512 && ff7t_sum(rect) == 512)
failures += ff7t_expect("rect adaptive floor", rect[0] > rect[1] && rect[1] >= 32)

# Independent retry clocks remove only the backed-off child from scheduling.
retry = i64[2]
retry[0] = 6
retry[1] = 0
sched = i64[2]
ready_count = ff7_fill_rect_sched_ready(5, ready, retry, sched) ## i64
failures += ff7t_expect("backoff masks one child", ready_count == 1 && sched[0] == 0 && sched[1] == 1)
single_used = ff7_rect_pool_allocation(pool_budget, 5, sched, exposure, rewards, rect) ## i64
failures += ff7t_expect("backoff returns reserve", single_used == 256 && rect[0] == 0 && rect[1] == 256)
ready_count = ff7_fill_rect_sched_ready(6, ready, retry, sched)
failures += ff7t_expect("backoff expires", ready_count == 2 && sched[0] == 1 && sched[1] == 1)
failures += ff7t_expect("composition clean idle", ff7_composition_due(0, 10, 0) == 0)
failures += ff7t_expect("composition retry withheld", ff7_composition_due(1, 9, 10) == 0)
failures += ff7t_expect("composition retry due", ff7_composition_due(1, 10, 10) == 1)

# Role 10 aggregates all rank-debt contexts.  A physical slot-10 debt cannot
# hide evidence from slots 11/12 or debt-zero rectangular children.
launch_debt = i64[15]
launch_debt[0] = 2
launch_debt[10] = 3
transition_exposure = i64[11 * ffkp_context_count()]
transition_rewards = i64[11 * ffkp_context_count()]
role0_index = ffkp_context(7, 2) ## i64
transition_exposure[role0_index] = 11
transition_rewards[role0_index] = 22
debt = 0 ## i64
while debt < 4
  role10_index = 10 * ffkp_context_count() + ffkp_context(7, debt) ## i64
  transition_exposure[role10_index] = debt + 1
  transition_rewards[role10_index] = (debt + 1) * 10
  debt += 1
context_exposure = i64[11]
context_rewards = i64[11]
z = ff7_fill_contextual_evidence(7, launch_debt, transition_exposure, transition_rewards, context_exposure, context_rewards) ## i64
failures += ff7t_expect("ordinary role contextual evidence", context_exposure[0] == 11 && context_rewards[0] == 22)
failures += ff7t_expect("role10 debt aggregation", context_exposure[10] == 10 && context_rewards[10] == 100)

# Both component labels have fixed fields; changing state and multi-digit
# counters cannot jiggle the paired row.  Retry and composer failure are
# explicit without turning the entire fleet health banner red.
left_active = ff7_rect_pool_label("rect-3x3x4", 256, 29, 1, 0, 0, 0, 1, 1, 5, 0, 0)
right_active = ff7_rect_pool_label("rect-3x4x4", 256, 38, 1, 0, 0, 0, 1, 1, 5, 0, 0)
left_retry = ff7_rect_pool_label("rect-3x3x4", 0, 29, 12, 11, 1234567, 12, 1, 0, 5, 9, 3)
right_retry = ff7_rect_pool_label("rect-3x4x4", 0, 38, 12, 11, 1234567, 12, 1, 0, 5, 9, 3)
active_row = ff_tui_gpu_pool_pair(left_active, 1, 1, right_active, 1, 1, 160)
retry_row = ff_tui_gpu_pool_pair(left_retry, 1, 1, right_retry, 1, 1, 160)
# The requested 160 is terminal-column width.  String.size counts UTF-8 bytes,
# so the two three-byte bullet markers add four bytes while preserving 160
# visible columns.
failures += ff7t_expect("rect TUI fixed visible width", active_row.size() == 164 && retry_row.size() == active_row.size())
failures += ff7t_expect("rect TUI retry visible", retry_row.include?("retry"))
failures += ff7t_expect("rect TUI cfail visible", retry_row.include?("cfail3"))

# The previous exact r250 frontier is deliberately retained as a +2 shoulder
# of the new r248 block construction, and the helper remains gated to 7x7/r248.
root = capture("pwd").strip()
n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
leader = i64[state_size]
leader_path = root + "/benchmarks/matmul/metaflip/matmul_7x7_rank248_d2952_sedoglavic_gf2.txt"
leader_rank = ffw_load_scheme_cap(leader, leader_path, n, capacity, 701, 4, 4, 1000, 250) ## i64
failures += ff7t_expect("rank248 leader exact", leader_rank == 248 && ffw_verify_best_exact(leader, n) == 1)
near2 = []
signatures = []
uses = []
successes = []
counters = i64[5]
added = ff7_add_known_7x7_shoulder(root, leader, n, capacity, state_size, 4, 4, 1000, 250, near2, signatures, uses, successes, 16, 8, counters) ## i64
failures += ff7t_expect("rank250 shoulder admitted", added == 1 && near2.size() == 1)
if near2.size() == 1
  failures += ff7t_expect("rank250 shoulder exact", ffw_best_rank(near2[0]) == 250 && ffw_verify_best_exact(near2[0], n) == 1)
before_wrong_n = near2.size() ## i64
wrong_n_added = ff7_add_known_7x7_shoulder(root, leader, 6, capacity, state_size, 4, 4, 1000, 250, near2, signatures, uses, successes, 16, 8, counters) ## i64
failures += ff7t_expect("rank250 shoulder gate", wrong_n_added == 0 && near2.size() == before_wrong_n)

# New rank-247 leader retains every old rank-248 component as a +1 shoulder.
leader247 = i64[state_size]
leader247_path = root + "/benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
leader247_rank = ffw_load_scheme_cap(leader247, leader247_path, n, capacity, 751, 4, 4, 1000, 250) ## i64
failures += ff7t_expect("rank247 leader exact", leader247_rank == 247 && ffw_verify_best_exact(leader247, n) == 1)
frontier247 = ffp_frontier_seed_paths(7)
failures += ff7t_expect("fourteen rank247 restart representatives", frontier247.size() == 14)
beam_child_active = 0 ## i64
affine_child_active = 0 ## i64
dominated_parent_active = 0 ## i64
frontier247_state = i64[state_size]
i = 0 ## i64
while i < frontier247.size()
  if frontier247[i].ends_with?("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt")
    beam_child_active = 1
  if frontier247[i].ends_with?("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt")
    affine_child_active = 1
  if frontier247[i].ends_with?("matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt") || frontier247[i].ends_with?("matmul_7x7_rank247_d3098_affine_code_gf2.txt")
    dominated_parent_active = 1
  frontier247_rank = ffw_load_scheme_cap(frontier247_state, root + "/" + frontier247[i], n, capacity, 761 + i, 4, 4, 1000, 250) ## i64
  failures += ff7t_expect("rank247 restart exact", frontier247_rank == 247 && ffw_verify_best_exact(frontier247_state, n) == 1)
  i += 1
failures += ff7t_expect("promoted CUDA children active", beam_child_active == 1 && affine_child_active == 1)
failures += ff7t_expect("dominated provenance parents inactive", dominated_parent_active == 0)
near1 = []
signatures1 = []
uses1 = []
successes1 = []
counters1 = i64[5]
added1 = ff7_add_known_7x7_rank247_shoulders(root, leader247, n, capacity, state_size, 4, 4, 1000, 250, near1, signatures1, uses1, successes1, 16, 8, counters1) ## i64
failures += ff7t_expect("four rank248 shoulders admitted", added1 == 4 && near1.size() == 4)
i = 0
while i < near1.size()
  failures += ff7t_expect("rank248 +1 shoulder exact", ffw_best_rank(near1[i]) == 248 && ffw_verify_best_exact(near1[i], n) == 1)
  i += 1

if failures > 0
  << "flipfleet_7x7_pool_test: " + failures.to_s() + " failure(s)"
  exit(1)
<< "flipfleet_7x7_pool_test: all checks passed"
