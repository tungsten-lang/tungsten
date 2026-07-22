use ../lib/metaflip/rect
use ../lib/metaflip/rect/cpu_pool

if ffrcp_split_cadence(3, 3, 4, 0, 1, 1) != 2000
  << "FAIL rectangular CPU cadence leaked to another shape"
  exit(1)
if ffrcp_split_cadence(2, 2, 9, 0, 4, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 2, 4, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 3, 4, 0) != 8000
  << "FAIL rectangular CPU cadence wide-shard lane"
  exit(1)
if ffrcp_split_cadence(2, 2, 9, 0, 1, 0 - 1) != 2000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 0) != 2000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 1) != 8000 || ffrcp_split_cadence(2, 2, 9, 0, 1, 2) != 2000
  << "FAIL rectangular CPU cadence one-worker alternation"
  exit(1)

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

phase_moves = i64[3]
z = ffrp_campaign_budgets(10000, phase_moves) ## i64
elapsed = i64[workers]
starts = []
threads = []
done = Channel.new(workers)
lane = 0
while lane < workers
  start = Channel.new(1)
  starts.push(start)
  split_cadence = 2000 ## i64
  if lane == 1
    split_cadence = 8000
  threads.push(ffrcp_spawn(states, lane, phase_moves, split_cadence, elapsed, start, done))
  lane += 1

lane = 0
while lane < workers
  starts[lane].send(1)
  lane += 1
lane = 0
while lane < workers
  completed = done.recv() ## i64
  if completed < 0 || completed >= workers
    << "FAIL rectangular CPU pool completion slot"
    exit(1)
  lane += 1

old_lane0 = states[0]
if ffr_moves(old_lane0) != 10000
  << "FAIL rectangular CPU pool first epoch moves=" + ffr_moves(old_lane0).to_s()
  exit(1)

# Replace one coordinator slot while every worker is parked. The persistent
# lane must reread the slot after its next start-channel acquire.
replacement = i64[state_size]
replacement_rank = ffr_init_naive_cap(replacement, n, m, p, capacity, 59003, 4, 4, 1000, 250) ## i64
if replacement_rank < 1
  << "FAIL rectangular CPU pool replacement init"
  exit(1)
states[0] = replacement

lane = 0
while lane < workers
  starts[lane].send(1)
  lane += 1
lane = 0
while lane < workers
  completed = done.recv() ## i64
  lane += 1

stopped = ffrcp_stop(starts, threads, workers) ## i64
if stopped != 1
  << "FAIL rectangular CPU pool stop"
  exit(1)
if ffr_moves(old_lane0) != 10000
  << "FAIL parked rectangular state mutated after slot replacement"
  exit(1)
if ffr_moves(states[0]) != 10000 || ffr_moves(states[1]) != 20000
  << "FAIL rectangular CPU pool second epoch moves=" + ffr_moves(states[0]).to_s() + "/" + ffr_moves(states[1]).to_s()
  exit(1)
if ffw_split_attempts(states[1]) < 1
  << "FAIL rectangular CPU pool cold cadence never attempted a split"
  exit(1)
if ffr_verify_current_exact(states[0], n, m, p) != 1 || ffr_verify_current_exact(states[1], n, m, p) != 1
  << "FAIL rectangular CPU pool exactness"
  exit(1)

<< "PASS rectangular persistent CPU pool epochs=2 replacement=1"
