use ../lib/metaflip/rect/campaign

# Per-epoch coordinator costs paid by a rolling rectangular island between its
# publish and relaunch: exact gate, slot copy, and one start/done round trip.

n = 4 ## i64
m = 5 ## i64
p = 7 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
state_size = ffr_state_size(capacity) ## i64
repo_root = "lib/metaflip"
state = i64[state_size]
rank = ffr_load_scheme_cap(state, repo_root + "/" + ffrp_seed_rel(n, m, p), n, m, p, capacity, 81001, 4, 4, 1000, 250) ## i64
if rank < 1
  << "FAIL seed"
  exit(1)
z = ffr_work(state, 50000) ## i64
z = ffr_walk(state, 400000)
z = ffr_wander(state, 50000)
exact_words = ffw_verify_scratch_words(n, m, p) ## i64
exact_scratch = i64[exact_words]
pair_words = ffpc_scratch_words(capacity) ## i64
pair_scratch = i64[pair_words]

iterations = 200 ## i64
t0 = ccall("__w_clock_ms") ## i64
i = 0 ## i64
while i < iterations
  z = ffpc_gate_rect_best(state, n, m, p, pair_scratch, pair_words, exact_scratch, exact_words)
  i += 1
gate_us = (ccall("__w_clock_ms") - t0) * 1000 / iterations ## i64

copy = i64[state_size]
t0 = ccall("__w_clock_ms")
i = 0
while i < iterations
  z = ffcp_copy_words(copy, state, state_size)
  i += 1
copy_us = (ccall("__w_clock_ms") - t0) * 1000 / iterations ## i64

t0 = ccall("__w_clock_ms")
i = 0
while i < iterations
  z = ffr_walk(state, 1000)
  i += 1
walk_us = (ccall("__w_clock_ms") - t0) * 1000 / iterations ## i64

# One-lane pool round trip with a one-move epoch: channel handoff + copies.
states = []
states.push(state)
steps = i64[1]
steps[0] = 1
modes = i64[1]
modes[0] = 4
cadences = i64[1]
cadences[0] = 2000
elapsed = i64[1]
pool = MetaflipCPUPool.new(states, state_size, modes, steps, i64[1], i64[7], i64[1], 1, i64[9], elapsed, cadences)
t0 = ccall("__w_clock_ms")
i = 0
while i < iterations
  z = pool.launch_idle()
  z = pool.begin_intake()
  z = pool.collect(1)
  i += 1
trip_us = (ccall("__w_clock_ms") - t0) * 1000 / iterations ## i64
z = pool.stop_commands()

<< "RECT_INTAKE_GAP state_words=" + state_size.to_s() + " gate_us=" + gate_us.to_s() + " copy_us=" + copy_us.to_s() + " walk1k_us=" + walk_us.to_s() + " pool_trip_us=" + trip_us.to_s()
