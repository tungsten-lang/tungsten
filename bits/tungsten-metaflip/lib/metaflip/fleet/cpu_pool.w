# Persistent CPU worker pool for the pure-Tungsten Metaflip coordinator.
#
# A worker owns one OS thread for the lifetime of a campaign.  The coordinator
# publishes a round by writing the shared mailboxes and then sending `1` on the
# worker's private start channel.  The channel mutex is the release/acquire
# boundary for state-slot replacement and control updates; completion uses one
# shared, bounded channel.  Sending `0` stops a parked worker.
#
# Modes:
#   0 ordinary metaflip walk
#   1 frozen-core/fringe walk
#   2 tuned control-race walk
#   3 accepted-state cycle-watch walk

-> ffcp_spawn(state_slots, slot, mode, round_steps, core_slots, controls, recent, recent_capacity, stats, elapsed_ms, start_channel, done_channel)
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
        if mode == 0
          result = ffw_walk(worker_state, round_steps[slot])
        if mode == 1
          result = ffw_walk_fringe(worker_state, round_steps[slot], core_slots[0])
        if mode == 2
          result = ffw_walk_tuned(worker_state, round_steps[slot], controls)
        if mode == 3
          result = ffw_walk_cycle_watch(worker_state, round_steps[slot], recent, recent_capacity, stats)
        elapsed_ms[slot] = ccall("__w_clock_ms") - t0
        # Keep the hot result live through the end of the epoch.  The result is
        # intentionally not sent: all mutable search state already lives in
        # the worker's stable state slot.
        if result < 0
          elapsed_ms[slot] = elapsed_ms[slot]
        done_channel.send(slot)
    0
