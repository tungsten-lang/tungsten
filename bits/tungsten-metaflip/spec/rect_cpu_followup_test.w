use ../lib/metaflip/rect/campaign

-> followup_check(label, condition) (String bool) i64
  if !condition
    << "FAIL rectangular CPU followup: " + label
    exit(1)
  1

z = followup_check("barrier and overlap policy", ffrc_cpu_gpu_mode("") == 1 && ffrc_cpu_gpu_mode("barrier") == 0 && ffrc_cpu_gpu_mode("overlap") == 1 && ffrc_cpu_gpu_mode("invalid") == -1)
z = followup_check("short quota unchanged", ffrcp_followup_steps(10000, 50) == 10000 && ffrcp_followup_steps(10000, 0) == 10000)
z = followup_check("slow quota is split", ffrcp_followup_steps(10000, 400) == 5000 && ffrcp_followup_steps(10000, 401) == 3333)
z = followup_check("invalid and minimum quota", ffrcp_followup_steps(0, 400) == 0 && ffrcp_followup_steps(1, 1000) == 1)
z = followup_check("overflow-free quota", ffrcp_followup_steps(9223372036854775807, 201) == 4611686018427387903)

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
  starts = []
  threads = []
  phase_moves = i64[3]
  elapsed = i64[workers]
  totals = i64[workers]
  before = i64[workers]
  done = Channel.new(workers)
  lane = 0 ## i64
  while lane < workers
    state = i64[size]
    rank = ffr_init_naive_cap(state,n,m,p,capacity,900001+lane*97+shape*131,4,4,1000,250) ## i64
    z = followup_check("initialization", rank > 0)
    copy = i64[size]
    i = 0 ## i64
    while i < size
      copy[i] = state[i]
      i += 1
    states.push(state)
    reference.push(copy)
    start = Channel.new(1)
    starts.push(start)
    cadence = 2000 ## i64
    if lane == 1
      cadence = 8000
    totals[lane] = 0
    threads.push(ffrcp_spawn(states,lane,phase_moves,cadence,elapsed,start,done))
    lane += 1
  total_steps = 0 ## i64
  batch = 0 ## i64
  while batch < 9
    steps = 10003 + batch*137 ## i64
    total_steps += steps
    z = ffrp_campaign_budgets(steps,phase_moves)
    z = followup_check("phase partition", phase_moves[0]+phase_moves[1]+phase_moves[2] == steps)
    lane = 0
    while lane < workers
      before[lane] = totals[lane]
      lane += 1
    z = ffrcp_dispatch(starts,elapsed,workers)
    lane = 0
    while lane < workers
      ref = reference[lane]
      if lane == 0
        z = ffr_work(ref,phase_moves[0])
        z = ffr_walk(ref,phase_moves[1])
        z = ffr_wander(ref,phase_moves[2])
      else
        z = ffrcp_work_cadence(ref,phase_moves[0],8000)
        z = ffrcp_walk_cadence(ref,phase_moves[1],8000)
        z = ffrcp_wander_cadence(ref,phase_moves[2],8000)
      lane += 1
    slowest = ffrcp_collect(done,elapsed,totals,workers) ## i64
    lane = 0
    while lane < workers
      z = followup_check("accumulated worker time", totals[lane] == before[lane]+elapsed[lane] && slowest >= elapsed[lane])
      z = followup_check("all batches counted", ffr_moves(states[lane]) == total_steps)
      i = 0 ## i64
      while i < size
        if states[lane][i] != reference[lane][i]
          << "state mismatch shape="+label+" batch="+batch.to_s()+" lane="+lane.to_s()+" word="+i.to_s()+" actual="+states[lane][i].to_s()+" reference="+reference[lane][i].to_s()
        z = followup_check("full state continuation", states[lane][i] == reference[lane][i])
        i += 1
      z = followup_check("exact current", ffr_verify_current_exact(states[lane],n,m,p) == 1)
      z = followup_check("exact best", ffr_verify_best_exact(states[lane],n,m,p) == 1)
      # Verification increments state diagnostics; apply it to both copies.
      z = followup_check("reference current", ffr_verify_current_exact(reference[lane],n,m,p) == 1)
      z = followup_check("reference best", ffr_verify_best_exact(reference[lane],n,m,p) == 1)
      lane += 1
    batch += 1
  z = ffrcp_stop(starts,threads,workers)
  << "PASS rectangular CPU followup shape="+label+" batches="+batch.to_s()+" moves_per_lane="+total_steps.to_s()
  shape += 1
<< "PASS rectangular CPU followup full-state continuation and timing"
