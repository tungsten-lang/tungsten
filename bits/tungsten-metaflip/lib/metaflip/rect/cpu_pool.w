# Persistent CPU worker pool for rectangular Metaflip campaigns.
#
# Every island owns one OS thread for the lifetime of the campaign. The
# coordinator publishes the current three-phase budget, then releases each
# worker through its private start channel. A shared completion channel forms
# the round barrier. Workers reread `state_slots[slot]` after every acquire so
# a coordinator rebase or manual reseed takes effect on the next epoch.

# The 2x2x9 frontier benefits from a colder rank-debt split cadence, but the
# measured effect is continuation/side-door value rather than a direct record
# hit. Preserve the 2,000-move baseline on every other shape and on all but
# one wide-shard lane. A one-worker portfolio child alternates cadences across
# its already-salted exact restarts, so this experiment never monopolizes its
# only long-lived search stream.
-> ffrcp_split_cadence(n, m, p, slot, workers, restart_door_ticket) (i64 i64 i64 i64 i64 i64) i64
  if n != 2 || m != 2 || p != 9
    return 2000
  if workers > 1 && slot == workers - 1
    return 8000
  if workers == 1 && restart_door_ticket >= 0 && (restart_door_ticket & 1) != 0
    return 8000
  2000

# Cold-lane twin of `ffr_one`. Baseline workers never enter this helper, so
# the ordinary rectangular hot loop retains its exact instruction path.
-> ffrcp_one_cadence(st, mode, split_cadence) (i64[] i64 i64) i64
  result = 0 ## i64
  do_split = 0 ## i64
  if mode != 0 && split_cadence > 0 && st[13] > 0 && (st[13] % split_cadence) == 0
    do_split = 1
  if do_split == 1
    result = ffr_try_split(st)
  if do_split == 0
    result = ffw_try_flip(st, mode)
  st[13] = st[13] + 1
  st[42] = mode
  if mode == 0
    st[34] = st[34] + 1
  if mode != 0
    st[35] = st[35] + 1
  if st[7] > 0 && st[6] > st[7] + st[10]
    z = ffw_restore_best(st) ## i64
  result

-> ffrcp_work_cadence(st, steps, split_cadence) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < steps
    z = ffrcp_one_cadence(st, 0, split_cadence) ## i64
    i += 1
  st[7]

-> ffrcp_wander_cadence(st, steps, split_cadence) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < steps
    z = ffrcp_one_cadence(st, 1, split_cadence) ## i64
    i += 1
  st[7]

-> ffrcp_walk_cadence(st, steps, split_cadence) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < steps
    mode = 0 ## i64
    if st[10] > st[11]
      mode = 1
    z = ffrcp_one_cadence(st, mode, split_cadence) ## i64
    if st[13] >= st[14]
      z = ffw_advance_zone(st)
    i += 1
  st[7]

-> ffrcp_spawn(state_slots, slot, phase_moves, split_cadence, elapsed_ms, start_channel, done_channel)
  Thread.new ->
    running = 1 ## i64
    while running == 1
      command = start_channel.recv() ## i64
      if command == 0
        running = 0
      if command != 0
        worker_state = state_slots[slot]
        t0 = ccall("__w_clock_ms") ## i64
        result = 0 ## i64
        if split_cadence == 2000
          result = ffr_work(worker_state, phase_moves[0])
          result = ffr_walk(worker_state, phase_moves[1])
          result = ffr_wander(worker_state, phase_moves[2])
        if split_cadence != 2000
          result = ffrcp_work_cadence(worker_state, phase_moves[0], split_cadence)
          result = ffrcp_walk_cadence(worker_state, phase_moves[1], split_cadence)
          result = ffrcp_wander_cadence(worker_state, phase_moves[2], split_cadence)
        elapsed_ms[slot] = ccall("__w_clock_ms") - t0
        # Keep the search result live through the epoch without boxing it into
        # the channel; all mutable state already resides in the stable slot.
        if result < 0
          elapsed_ms[slot] = elapsed_ms[slot]
        done_channel.send(slot)
    0

-> ffrcp_stop(start_channels, threads, workers)
  lane = 0 ## i64
  while lane < workers
    start_channels[lane].send(0)
    lane += 1
  lane = 0
  while lane < workers
    result = ccall("w_thread_join_release", threads[lane])
    threads[lane] = nil
    lane += 1
  1
