# Persistent CPU worker pool for rectangular Metaflip campaigns.
#
# Every island owns one OS thread for the lifetime of the campaign. The
# coordinator publishes the current three-phase budget, then releases each
# worker through its private start channel. A shared completion channel forms
# the round barrier. Workers reread `state_slots[slot]` after every acquire so
# a coordinator rebase or manual reseed takes effect on the next epoch.

-> ffrcp_spawn(state_slots, slot, phase_moves, elapsed_ms, start_channel, done_channel)
  Thread.new ->
    running = 1 ## i64
    while running == 1
      command = start_channel.recv() ## i64
      if command == 0
        running = 0
      if command != 0
        worker_state = state_slots[slot]
        t0 = ccall("__w_clock_ms") ## i64
        result = ffr_work(worker_state, phase_moves[0]) ## i64
        result = ffr_walk(worker_state, phase_moves[1])
        result = ffr_wander(worker_state, phase_moves[2])
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
