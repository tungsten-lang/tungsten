# Per-slot timing diagnostic for the square Metaflip CPU pool.
#
#   cpu_pool_straggler_bench [workers] [steps] [rounds] [profile] [seed-path] [target-ms]
#
# Profiles:
#   ordinary  every lane runs ffw_walk
#   fleet     one fringe, one tuned, and one cycle-watch lane, matching fleet.w
#
# All lanes start from the same exact 7x7 rank-247 scheme.  The benchmark
# reports the completion order and each lane's wall time, plus
# `effective_parallelism = sum(worker_ms) / round_wall_ms`.  That ratio makes
# a barrier tail visible without an OS-specific profiler: it is near J when
# the workers overlap uniformly and collapses when most lanes park behind one
# straggler.

use ../lib/metaflip/scheme
use ../lib/metaflip/fleet/cpu_pool

args = argv()
workers = 12 ## i64
steps = 500000 ## i64
rounds = 3 ## i64
profile = "ordinary" ## String
if args.size() > 0
  workers = args[0].to_i()
if args.size() > 1
  steps = args[1].to_i()
if args.size() > 2
  rounds = args[2].to_i()
if args.size() > 3
  profile = args[3]
if workers < 1
  workers = 1
if steps < 1
  steps = 1
if rounds < 1
  rounds = 1
if profile != "ordinary" && profile != "fleet"
  << "FAIL unknown profile=" + profile
  exit(1)
target_ms = 0 ## i64
if args.size() > 5
  target_ms = args[5].to_i()
if target_ms < 0
  target_ms = 0

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
seed_path = "lib/metaflip/seeds/gf2/matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt" ## String
if args.size() > 4
  seed_path = args[4]
base = i64[state_size]
base_rank = ffw_load_scheme_cap(base, seed_path, n, capacity, 71001, 8, 7, 500000000, 100000000) ## i64
if base_rank != 247
  << "FAIL 7x7 seed load rank=" + base_rank.to_s()
  exit(1)

states = []
lane = 0 ## i64
while lane < workers
  state = i64[state_size]
  cloned = ffw_reseed_from(state, base, 72001 + lane * 977) ## i64
  if cloned != 247
    << "FAIL clone lane=" + lane.to_s() + " rank=" + cloned.to_s()
    exit(1)
  states.push(state)
  lane += 1

round_steps = i64[workers]
worker_modes = i64[workers]
epoch_eligible = i64[workers]
epoch_scratch = i64[workers]
elapsed_ms = i64[workers]
core_slots = i64[1]
core_slots[0] = 198
controls = i64[7]
# A representative balanced control arm.  The ordinary profile never reads it.
controls[0] = 2000
controls[1] = 6
controls[2] = 300000
controls[3] = 1
controls[4] = 12
controls[5] = 7
controls[6] = 60
recent_capacity = 512 ## i64
recent = i64[recent_capacity]
stats = i64[9]
starts = []
threads = []
done = Channel.new(workers)

lane = 0
while lane < workers
  mode = 0 ## i64
  if profile == "fleet" && workers >= 4
    if lane == workers - 3
      mode = 1
    if lane == workers - 2
      mode = 3
    if lane == workers - 1
      mode = 2
  worker_modes[lane] = mode
  epoch_eligible[lane] = 1
  if mode == 1
    epoch_eligible[lane] = 0
  round_steps[lane] = steps
  # The production fringe lane begins at one fifth of the ordinary budget.
  if mode == 1
    round_steps[lane] = steps / 5
    if round_steps[lane] < 1
      round_steps[lane] = 1
  start = Channel.new(1)
  starts.push(start)
  threads.push(ffcp_spawn(states, lane, mode, round_steps, core_slots, controls, recent, recent_capacity, stats, elapsed_ms, start, done))
  lane += 1

completion = i64[workers]
sorted = i64[workers]
epoch_steps = steps ## i64
epoch = 0 ## i64
while epoch < rounds
  lane = 0
  while lane < workers
    round_steps[lane] = epoch_steps
    if worker_modes[lane] == 1
      round_steps[lane] = epoch_steps / 5
      if round_steps[lane] < 1
        round_steps[lane] = 1
    elapsed_ms[lane] = 0
    starts[lane].send(1)
    lane += 1
  wall_start = ccall_nobox("__w_clock_ns_raw") ## i64
  lane = 0
  while lane < workers
    completed = done.recv() ## i64
    if completed < 0 || completed >= workers
      << "FAIL completion slot=" + completed.to_s()
      exit(1)
    completion[lane] = completed
    lane += 1
  wall_ns = ccall_nobox("__w_clock_ns_raw") - wall_start ## i64
  if wall_ns < 1
    wall_ns = 1

  sum_ms = 0 ## i64
  minimum = 9223372036854775807 ## i64
  maximum = 0 ## i64
  lane = 0
  while lane < workers
    value = elapsed_ms[lane] ## i64
    sorted[lane] = value
    sum_ms += value
    if value < minimum
      minimum = value
    if value > maximum
      maximum = value
    lane += 1
  # Insertion sort is outside the measured region and keeps this diagnostic
  # independent of generic collection sorting/boxing.
  lane = 1
  while lane < workers
    value = sorted[lane] ## i64
    scan = lane - 1 ## i64
    while scan >= 0 && sorted[scan] > value
      sorted[scan + 1] = sorted[scan]
      scan -= 1
    sorted[scan + 1] = value
    lane += 1
  wall_ms = (wall_ns + 999999) / 1000000 ## i64
  effective_milli = sum_ms * 1000 / wall_ms ## i64
  total_moves = 0 ## i64
  lane = 0
  while lane < workers
    total_moves += round_steps[lane]
    lane += 1
  aggregate_milli_mps = total_moves * 1000000000 / wall_ns ## i64
  p50 = sorted[(workers - 1) / 2] ## i64
  p90 = sorted[(workers - 1) * 9 / 10] ## i64
  p99 = sorted[(workers - 1) * 99 / 100] ## i64
  line = "CPU_POOL_ROUND profile=" + profile + " workers=" + workers.to_s() + " epoch=" + epoch.to_s() ## String
  line += " nominal_steps=" + steps.to_s() + " epoch_steps=" + epoch_steps.to_s() + " wall_ns=" + wall_ns.to_s()
  line += " aggregate_milli_mps=" + aggregate_milli_mps.to_s()
  line += " effective_parallelism_milli=" + effective_milli.to_s()
  line += " worker_ms_min_p50_p90_p99_max=" + minimum.to_s() + "," + p50.to_s() + "," + p90.to_s() + "," + p99.to_s() + "," + maximum.to_s()
  << line
  order_line = "CPU_POOL_ORDER epoch=" + epoch.to_s() ## String
  lane = 0
  while lane < workers
    order_line += " " + completion[lane].to_s()
    lane += 1
  << order_line
  lane_line = "CPU_POOL_LANES epoch=" + epoch.to_s() ## String
  lane = 0
  while lane < workers
    lane_line += " " + lane.to_s() + ":" + elapsed_ms[lane].to_s()
    lane += 1
  << lane_line
  if target_ms > 0
    median_ms = ffcp_median_elapsed(elapsed_ms, epoch_eligible, workers, epoch_scratch) ## i64
    epoch_steps = ffcp_adapt_epoch_steps(epoch_steps, median_ms, target_ms, steps)
  epoch += 1

lane = 0
while lane < workers
  starts[lane].send(0)
  lane += 1
lane = 0
while lane < workers
  # The worker returns integer zero, which is a valid result rather than a
  # boolean join status.  Releasing it is the success condition here.
  joined = ccall("w_thread_join_release", threads[lane])
  lane += 1

if ffw_verify_current_exact(states[0], n) != 1 || ffw_verify_current_exact(states[workers - 1], n) != 1
  << "FAIL final exact gate"
  exit(1)
<< "PASS cpu pool straggler diagnostic"
