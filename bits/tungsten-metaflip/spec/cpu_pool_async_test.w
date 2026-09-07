use ../lib/metaflip/scheme
use ../lib/metaflip/fleet/cpu_pool

-> expect(label, condition) (String bool) i64
  if !condition
    << "FAIL asynchronous CPU pool: " + label
    exit(1)
  1

-> same_words(a, b, count) (i64[] i64[] i64) bool
  i = 0 ## i64
  while i < count
    if a[i] != b[i]
      return false
    i += 1
  true

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
size = ffw_state_size(capacity) ## i64
states = []
oracle = i64[size]
initial = i64[size]
i = 0 ## i64
while i < 2
  state = i64[size]
  z = ffw_init_naive_cap(state, n, capacity, 919 + i, 8, 1000000, 1000000000, 1000000000)
  states.push(state)
  i += 1
z = ffcp_copy_words(oracle, states[0], size)
z = ffcp_copy_words(initial, states[1], size)
steps = i64[2]
steps[0] = 1024
steps[1] = 30000000
modes = i64[2]
core = i64[1]
controls = i64[7]
recent = i64[512]
stats = i64[9]
elapsed = i64[2]
pool = MetaflipCPUPool.new(states, size, modes, steps, core, controls, recent, 512, stats, elapsed)
z = pool.launch_idle()
# Mutating the coordinator's next quota cannot affect an in-flight epoch.
steps[0] = 2048
z = pool.begin_intake()
z = pool.collect(0)
ready = pool.ready()
z = expect("fast lane finishes without slow lane", ready[0] == 1 && ready[1] == 0 && pool.active() == 1)
z = expect("live state never aliases published snapshot", same_words(states[1], initial, size))
z = ffw_walk(oracle, 1024)
z = expect("first continuation includes RNG and hash state", same_words(states[0], oracle, size))
z = pool.launch_idle()
z = expect("fast lane restarted while slow lane runs", pool.active() == 2)
z = pool.begin_intake()
z = pool.collect(0)
z = ffw_walk(oracle, 2048)
z = expect("second continuation is bitwise identical", same_words(states[0], oracle, size))
epochs = pool.epochs()
z = expect("independent lane progress", epochs[0] == 2 && epochs[1] == 0)
z = pool.collect(1)
z = expect("drain retains slow completion exactly once", pool.active() == 0 && epochs[1] == 1 && ffw_moves(states[1]) == 30000000)

# Reset/reseed is performed only after drain; the next publication must not
# resurrect the previous generation or retain its move counters.
z = ffw_init_naive_cap(states[0], n, capacity, 1719, 8, 1000000, 1000000000, 1000000000)
z = ffcp_copy_words(oracle, states[0], size)
steps[1] = 4096
z = pool.launch_idle()
z = pool.begin_intake()
z = pool.collect(1)
z = ffw_walk(oracle, 2048)
z = expect("reset continuation", same_words(states[0], oracle, size))
z = expect("reset does not replay old counters", ffw_moves(states[0]) == 2048)
z = expect("minimum epoch tracks complete fleet rounds", pool.minimum_epochs() == 2)
z = expect("exact first endpoint", ffw_verify_best_exact(states[0], n) == 1)
z = expect("exact late endpoint", ffw_verify_best_exact(states[1], n) == 1)
z = pool.stop_commands()
threads = pool.threads()
i = 0
while i < 2
  z = threads[i].join()
  i += 1
<< "PASS async CPU pool: independent completion, bounded snapshots, bitwise continuation, quota ownership, reset, drain, exactness"

# The three special lanes use private controls/stats as well as private states.
special_states = []
special_oracles = []
special_steps = i64[4]
special_modes = i64[4]
special_elapsed = i64[4]
special_stats = i64[9]
oracle_stats = i64[9]
special_recent = i64[512]
oracle_recent = i64[512]
old_controls = i64[7]
controls[0] = 2000
controls[1] = 6
controls[2] = 300000
controls[3] = 1
controls[4] = 12
controls[5] = 7
controls[6] = 60
z = ffcp_copy_words(old_controls, controls, 7)
core[0] = 80
i = 0
while i < 4
  state = i64[size]
  expected = i64[size]
  z = ffw_init_naive_cap(state, n, capacity, 7719 + i, 8, 1000000, 1000000000, 1000000000)
  z = ffcp_copy_words(expected, state, size)
  special_states.push(state)
  special_oracles.push(expected)
  special_steps[i] = 50000
  special_modes[i] = i
  i += 1
special = MetaflipCPUPool.new(special_states, size, special_modes, special_steps, core, controls, special_recent, 512, special_stats, special_elapsed)
z = special.launch_idle()
controls[0] = 0 - 1
core[0] = 0
z = special.begin_intake()
z = special.collect(1)
z = ffw_walk(special_oracles[0], 50000)
z = ffw_walk_fringe(special_oracles[1], 50000, 80)
z = ffw_walk_tuned(special_oracles[2], 50000, old_controls)
z = ffw_walk_cycle_watch(special_oracles[3], 50000, oracle_recent, 512, oracle_stats)
i = 0
while i < 4
  z = expect("special lane continuation " + i.to_s(), same_words(special_states[i], special_oracles[i], size))
  z = expect("special lane exact " + i.to_s(), ffw_verify_best_exact(special_states[i], n) == 1)
  i += 1
z = expect("cycle history stays worker-owned", same_words(special_recent, oracle_recent, 512))
z = special.stop_commands()
special_threads = special.threads()
i = 0
while i < 4
  z = ccall("w_thread_join_release", special_threads[i])
  i += 1
<< "PASS special CPU pool: fringe, tuned controls and cycle-watch continuation"
