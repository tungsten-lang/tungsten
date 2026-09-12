use ../lib/metaflip/rect
use ../lib/metaflip/rect/cpu_pool
use ../lib/metaflip/fleet/cpu_pool

if ffrcp_split_cadence(3, 3, 4, 0, 1, 1) != 2000
  << "FAIL rectangular CPU cadence leaked to another shape"
  exit(1)
if ffrcp_split_cadence(2, 2, 9, 0, 4, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 2, 4, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 3, 4, 0) != 8000
  << "FAIL rectangular CPU cadence wide-shard lane"
  exit(1)
if ffrcp_split_cadence(2, 2, 9, 0, 1, 0 - 1) != 2000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 1) != 8000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 2) != 2000
  << "FAIL rectangular CPU cadence one-worker alternation"
  exit(1)

# Rectangular islands run as fleet-pool mode 4: three-phase budgets derived
# from the lane's live step count, per-lane split cadence, rolling epochs.
n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
workers = 2 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
state_size = ffr_state_size(capacity) ## i64
states = []
lane = 0 ## i64
while lane < workers
  state = i64[state_size]
  rank = ffr_init_naive_cap(state, n, m, p, capacity, 51001 + lane * 97, 4, 4, 1000, 250) ## i64
  if rank < 1
    << "FAIL rectangular CPU pool state init"
    exit(1)
  states.push(state)
  lane += 1

steps = i64[workers]
modes = i64[workers]
cadences = i64[workers]
elapsed = i64[workers]
lane = 0
while lane < workers
  steps[lane] = 10000
  modes[lane] = 4
  cadences[lane] = 2000
  if lane == 1
    cadences[lane] = 8000
  lane += 1
pool = MetaflipCPUPool.new(states, state_size, modes, steps, i64[1], i64[7], i64[1], 1, i64[9], elapsed, cadences)
ready = pool.ready()

z = pool.launch_idle()
z = pool.begin_intake()
z = pool.collect(1)
if ready[0] != 1 || ready[1] != 1 || pool.minimum_epochs() != 1
  << "FAIL rectangular CPU pool first epoch publication"
  exit(1)
old_lane0 = states[0]
if ffr_moves(old_lane0) != 10000 || ffr_moves(states[1]) != 10000
  << "FAIL rectangular CPU pool first epoch moves=" + ffr_moves(old_lane0).to_s() + "/" + ffr_moves(states[1]).to_s()
  exit(1)

# Replace one coordinator slot while that lane is parked. The next launch
# copies the replacement into the lane's private live buffer; the old
# published buffer is never touched again.
replacement = i64[state_size]
replacement_rank = ffr_init_naive_cap(replacement, n, m, p, capacity, 59003, 4, 4, 1000, 250) ## i64
if replacement_rank < 1
  << "FAIL rectangular CPU pool replacement init"
  exit(1)
states[0] = replacement
z = pool.launch_idle()
z = pool.begin_intake()
z = pool.collect(1)
if ffr_moves(old_lane0) != 10000
  << "FAIL parked rectangular state mutated after slot replacement"
  exit(1)
if ffr_moves(states[0]) != 10000 || ffr_moves(states[1]) != 20000
  << "FAIL rectangular CPU pool second epoch moves=" + ffr_moves(states[0]).to_s() + "/" + ffr_moves(states[1]).to_s()
  exit(1)
if ffw_split_attempts(states[1]) < 1
  << "FAIL rectangular CPU pool cold cadence never attempted a split"
  exit(1)

# A bounded campaign parks each lane at exactly the epoch cap.
z = pool.launch_idle_below(3)
z = pool.begin_intake()
z = pool.collect(1)
launched = pool.launch_idle_below(3) ## i64
if launched != 0 || pool.active() != 0 || pool.minimum_epochs() != 3 || pool.lane_epochs(1) != 3
  << "FAIL rectangular CPU pool epoch cap launched=" + launched.to_s() + " min=" + pool.minimum_epochs().to_s()
  exit(1)
z = pool.begin_intake()
if pool.collect_within(5) != 0
  << "FAIL rectangular CPU pool bounded collect on a parked pool"
  exit(1)

# Rolling intake: a fast lane is published and relaunched while a slow lane
# is still walking; the slow lane's slot stays a stable snapshot meanwhile.
steps[0] = 1000
steps[1] = 4000000
slow_snapshot_moves = ffr_moves(states[1]) ## i64
z = pool.launch_idle()
z = pool.begin_intake()
published = pool.collect_within(5000) ## i64
if published != 1 || ready[0] != 1 || ready[1] != 0 || pool.busy_lane(1) != 1 || pool.busy_lane(0) != 0
  << "FAIL rectangular CPU pool rolling intake published=" + published.to_s() + " ready=" + ready[0].to_s() + "/" + ready[1].to_s()
  exit(1)
if ffr_moves(states[1]) != slow_snapshot_moves
  << "FAIL busy lane's published slot changed under the coordinator"
  exit(1)
relaunched = pool.launch_idle() ## i64
if relaunched != 2
  << "FAIL rectangular CPU pool relaunch active=" + relaunched.to_s()
  exit(1)
z = pool.begin_intake()
z = pool.collect(1)
if ffr_moves(states[0]) != 22000 || ffr_moves(states[1]) != 4030000
  << "FAIL rectangular CPU pool rolling moves=" + ffr_moves(states[0]).to_s() + "/" + ffr_moves(states[1]).to_s()
  exit(1)
if pool.lane_epochs(0) != 5 || pool.lane_epochs(1) != 4
  << "FAIL rectangular CPU pool epoch counts=" + pool.lane_epochs(0).to_s() + "/" + pool.lane_epochs(1).to_s()
  exit(1)
if ffr_verify_current_exact(states[0], n, m, p) != 1 || ffr_verify_current_exact(states[1], n, m, p) != 1
  << "FAIL rectangular CPU pool exactness"
  exit(1)
if ffr_verify_best_exact(states[0], n, m, p) != 1 || ffr_verify_best_exact(states[1], n, m, p) != 1
  << "FAIL rectangular CPU pool best exactness"
  exit(1)
z = pool.stop_commands()
threads = pool.threads()
lane = 0
while lane < workers
  result = ccall("w_thread_join_release", threads[lane])
  lane += 1

<< "PASS rectangular rolling CPU pool epochs=5/4 replacement=1 cap=1 rolling=1"
