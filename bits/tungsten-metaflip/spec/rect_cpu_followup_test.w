use ../lib/metaflip/rect/campaign

# Rectangular islands never park behind a producer: while a slow producer
# thread runs, the rolling pool keeps publishing and relaunching every lane,
# and each lane's full state continues exactly as a serial walk would.

-> followup_check(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular CPU followup: " + label
    exit(1)
  1

z = followup_check("barrier and overlap policy", ffrc_cpu_gpu_mode("") == 1 && ffrc_cpu_gpu_mode("barrier") == 0 && ffrc_cpu_gpu_mode("overlap") == 1 && ffrc_cpu_gpu_mode("invalid") == -1)
z = followup_check("duty percentage", ffrc_cpu_duty_percent(900, 100, 1, 1000) == 100 && ffrc_cpu_duty_percent(1800, 0, 4, 1000) == 45 && ffrc_cpu_duty_percent(1, 0, 0, 1000) == 0 && ffrc_cpu_duty_percent(5000, 0, 1, 1000) == 100)
ready = i64[4]
pending = i64[4]
ready[1] = 1
ready[3] = 1
z = followup_check("ready lane rotation", ffrc_pick_ready_lane(ready, pending, 4, 0) == 1 && ffrc_pick_ready_lane(ready, pending, 4, 1) == 3 && ffrc_pick_ready_lane(ready, pending, 4, 2) == 1)
pending[1] = 1
z = followup_check("pending lanes are skipped", ffrc_pick_ready_lane(ready, pending, 4, 0) == 3 && ffrc_pick_ready_lane(ready, pending, 4, 7) == 3)
pending[3] = 1
z = followup_check("no free ready lane", ffrc_pick_ready_lane(ready, pending, 4, 0) == -1)

# A delayed producer preserves its alternate current state but inherits the
# latest CPU best. Test rank and density progress, and invalid incumbents.
fixture_root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
incumbent = i64[ffr_state_size(128)]
z = followup_check("new incumbent fixture", ffr_load_scheme_cap(incumbent, fixture_root + "matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, 128, 901, 4, 4, 1000, 250) == 18)
case_number = 0 ## i64
while case_number < 2
  delayed = i64[ffr_state_size(128)]
  if case_number == 0
    z = followup_check("delayed rank fixture", ffr_init_naive_cap(delayed, 2, 2, 5, 128, 903, 4, 4, 1000, 250) == 20)
  else
    z = followup_check("delayed density fixture", ffr_load_scheme_cap(delayed, fixture_root + "matmul_2x2x5_rank18_d92_block_local_gl_gf2.txt", 2, 2, 5, 128, 907, 4, 4, 1000, 250) == 18)
  before = i64[delayed.size()]
  z = ffcp_copy_words(before, delayed, delayed.size())
  z = followup_check("carry newer island best", ffrc_preserve_island_best(delayed, incumbent, 2, 2, 5) == 1)
  z = followup_check("rank/density retained", ffr_best_rank(delayed) == 18 && ffr_best_bits(delayed) == 84)
  z = followup_check("both views exact", ffr_verify_best_exact(delayed, 2, 2, 5) == 1 && ffr_verify_current_exact(delayed, 2, 2, 5) == 1)
  z = followup_check("density delta retained", delayed[64] == ffr_current_bits(delayed) - ffr_best_bits(delayed))
  word = 0 ## i64
  while word < delayed.size()
    best_word = (word >= delayed[47] && word < delayed[47] + 18) || (word >= delayed[48] && word < delayed[48] + 18) || (word >= delayed[49] && word < delayed[49] + 18)
    if !best_word && word != 7 && word != 36 && word != 64 && word != 29 && word != 30 && word != 38
      z = followup_check("alternate continuation unchanged", delayed[word] == before[word])
    word += 1
  z = followup_check("worse/equal incumbent ignored", ffrc_preserve_island_best(delayed, before, 2, 2, 5) == 0)
  corrupt = i64[incumbent.size()]
  z = ffcp_copy_words(corrupt, incumbent, incumbent.size())
  corrupt[corrupt[47]] = 0
  z = followup_check("invalid incumbent ignored", ffrc_preserve_island_best(before, corrupt, 2, 2, 5) == 0)
  case_number += 1

labels = ["2x3x4", "2x2x9", "4x6x7"]
shape = 0 ## i64
while shape < labels.size()
  label = labels[shape]
  n = ffrp_n(label) ## i64
  m = ffrp_m(label) ## i64
  p = ffrp_p(label) ## i64
  workers = 2 ## i64
  capacity = ffr_default_capacity(n,m,p) ## i64
  size = ffr_state_size(capacity) ## i64
  states = []
  reference = []
  steps = i64[workers]
  modes = i64[workers]
  cadences = i64[workers]
  elapsed = i64[workers]
  phase_moves = i64[3]
  lane = 0 ## i64
  while lane < workers
    state = i64[size]
    rank = ffr_init_naive_cap(state,n,m,p,capacity,900001+lane*97+shape*131,4,4,1000,250) ## i64
    z = followup_check("initialization", rank > 0)
    copy = i64[size]
    z = ffcp_copy_words(copy, state, size)
    states.push(state)
    reference.push(copy)
    steps[lane] = 10003 + lane * 137
    modes[lane] = 4
    cadences[lane] = 2000
    if lane == 1
      cadences[lane] = 8000
    lane += 1
  pool = MetaflipCPUPool.new(states, size, modes, steps, i64[1], i64[7], i64[1], 1, i64[9], elapsed, cadences)
  pool_ready = pool.ready()

  # A producer that would have held the old round barrier for 400 ms.
  producer_done = i64[1]
  producer = Thread.new ->
    z = ccall("__w_sleep_ms", 400)
    producer_done[0] = 1
    true
  ticks = 0 ## i64
  walked_ms = 0 ## i64
  t_start = ccall("__w_clock_ms") ## i64
  while producer.alive?
    z = pool.launch_idle()
    z = pool.begin_intake()
    z = pool.collect_within(5)
    lane = 0
    while lane < workers
      if pool_ready[lane] != 0
        walked_ms += elapsed[lane]
      lane += 1
    ticks += 1
  joined = ffrc_thread_join_release(producer)
  z = pool.begin_intake()
  z = pool.collect(1)
  lane = 0
  while lane < workers
    if pool_ready[lane] != 0
      walked_ms += elapsed[lane]
    lane += 1
  wall_ms = ccall("__w_clock_ms") - t_start ## i64
  z = followup_check("islands walked while the producer ran", pool.minimum_epochs() >= 4 && producer_done[0] == 1)
  duty = ffrc_cpu_duty_percent(walked_ms, 0, workers, wall_ms) ## i64
  z = followup_check("islands were busy for most of the producer wait", duty >= 50)

  # Exact continuation: every published epoch equals a serial walk with the
  # same three-phase budgets applied the same number of times.
  lane = 0
  while lane < workers
    epochs = pool.lane_epochs(lane) ## i64
    z = ffrp_campaign_budgets(steps[lane], phase_moves)
    z = followup_check("phase partition", phase_moves[0]+phase_moves[1]+phase_moves[2] == steps[lane])
    ref = reference[lane]
    e = 0 ## i64
    while e < epochs
      if lane == 0
        z = ffr_work(ref,phase_moves[0])
        z = ffr_walk(ref,phase_moves[1])
        z = ffr_wander(ref,phase_moves[2])
      else
        z = ffrcp_work_cadence(ref,phase_moves[0],8000)
        z = ffrcp_walk_cadence(ref,phase_moves[1],8000)
        z = ffrcp_wander_cadence(ref,phase_moves[2],8000)
      e += 1
    z = followup_check("all epochs counted", ffr_moves(states[lane]) == epochs * steps[lane])
    i = 0 ## i64
    while i < size
      if states[lane][i] != ref[i]
        << "state mismatch shape="+label+" lane="+lane.to_s()+" word="+i.to_s()+" actual="+states[lane][i].to_s()+" reference="+ref[i].to_s()
      z = followup_check("full state continuation", states[lane][i] == ref[i])
      i += 1
    z = followup_check("exact current", ffr_verify_current_exact(states[lane],n,m,p) == 1)
    z = followup_check("exact best", ffr_verify_best_exact(states[lane],n,m,p) == 1)
    lane += 1
  z = pool.stop_commands()
  threads = pool.threads()
  lane = 0
  while lane < workers
    result = ccall("w_thread_join_release", threads[lane])
    lane += 1
  << "PASS rectangular CPU followup shape="+label+" ticks="+ticks.to_s()+" epochs="+pool.lane_epochs(0).to_s()+"/"+pool.lane_epochs(1).to_s()+" duty="+duty.to_s()
  shape += 1
<< "PASS rectangular CPU followup: islands keep walking while producers run, full-state continuation"
