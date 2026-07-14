use metaflip_worker
use flipfleet_cpu_experiments
use flipfleet_cpu_pool

-> ffcp_test_expect(name, condition)
  if condition == 0
    << "FAIL " + name
    exit(1)

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
first = i64[state_size]
second = i64[state_size]
peer = i64[state_size]
z = ffw_init_naive_cap(first, n, capacity, 101, 4, 4, 1000, 250) ## i64
z = ffw_init_naive_cap(second, n, capacity, 211, 4, 4, 1000, 250) ## i64
z = ffw_init_naive_cap(peer, n, capacity, 307, 4, 4, 1000, 250) ## i64

states = [first, peer]
round_steps = i64[2]
round_steps[0] = 2000
round_steps[1] = 2000
core_slots = i64[1]
controls = i64[7]
recent = i64[64]
stats = i64[9]
elapsed_ms = i64[2]
done = Channel.new(2)
starts = [Channel.new(1), Channel.new(1)]
workers = []
workers.push(ffcp_spawn(states, 0, 0, round_steps, core_slots, controls, recent, 64, stats, elapsed_ms, starts[0], done))
workers.push(ffcp_spawn(states, 1, 0, round_steps, core_slots, controls, recent, 64, stats, elapsed_ms, starts[1], done))

# First epoch mutates the original slot values.
starts[0].send(1)
starts[1].send(1)
z = done.recv()
z = done.recv()
first_moves = ffw_moves(first) ## i64
peer_moves = ffw_moves(peer) ## i64
ffcp_test_expect("first state advanced", first_moves == 2000)
ffcp_test_expect("peer state advanced", peer_moves == 2000)

# The coordinator may replace a state slot between epochs (strict drop,
# core/fringe refresh, or manual reseed).  The persistent worker must load the
# slot after the start-channel acquire, not retain its launch-time state.
states[0] = second
starts[0].send(1)
z = done.recv()
ffcp_test_expect("replacement state advanced", ffw_moves(second) == 2000)
ffcp_test_expect("old state stayed quiescent", ffw_moves(first) == first_moves)

# Swapping back proves repeated mailbox publication, not a one-time capture.
states[0] = first
starts[0].send(1)
z = done.recv()
ffcp_test_expect("restored state advanced", ffw_moves(first) == first_moves + 2000)
ffcp_test_expect("replacement stayed quiescent", ffw_moves(second) == 2000)

i = 0 ## i64
while i < 2
  starts[i].send(0)
  i += 1
i = 0
while i < 2
  workers[i].join
  i += 1

ffcp_test_expect("states remain exact", ffw_verify_best_exact(first, n) == 1 && ffw_verify_best_exact(second, n) == 1 && ffw_verify_best_exact(peer, n) == 1)
<< "flipfleet_cpu_pool_test: all checks passed"

