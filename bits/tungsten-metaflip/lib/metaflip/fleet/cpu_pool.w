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

# Return the lower median elapsed time of eligible workers.  `scratch` is
# campaign-owned so the round controller does not allocate at the barrier.
# A median (rather than the fastest lane or arithmetic mean) keeps one true
# straggler from setting every island's next quota.
-> ffcp_median_elapsed(elapsed_ms, eligible, workers, scratch) (i64[] i64[] i64 i64[]) i64
  count = 0 ## i64
  lane = 0 ## i64
  while lane < workers
    if eligible[lane] != 0 && elapsed_ms[lane] > 0
      value = elapsed_ms[lane] ## i64
      scan = count - 1 ## i64
      while scan >= 0 && scratch[scan] > value
        scratch[scan + 1] = scratch[scan]
        scan -= 1
      scratch[scan + 1] = value
      count += 1
    lane += 1
  if count == 0
    return 0
  scratch[(count - 1) / 2]

# Convert equal-move epochs into approximately equal-time epochs without
# changing any worker's sticky state.  The ordinary correction is deliberately
# smooth, while a >4x tail is corrected in one round: on a large synchronous
# fleet that tail otherwise parks every other OS thread at the barrier.  The
# 1/1024..4x nominal bounds preserve every lane and prevent a transient timing
# sample from monopolizing the next epoch.
-> ffcp_adapt_round_steps(current_steps, elapsed_ms, target_ms, nominal_steps) (i64 i64 i64 i64) i64
  current = current_steps ## i64
  if current < 1
    current = 1
  if elapsed_ms < 1 || target_ms < 1 || nominal_steps < 1
    return current
  proposed = current * target_ms / elapsed_ms ## i64
  minimum = nominal_steps / 1024 ## i64
  if minimum < 1
    minimum = 1
  maximum = nominal_steps * 4 ## i64
  if maximum < nominal_steps
    maximum = nominal_steps
  if proposed < minimum
    proposed = minimum
  if proposed > maximum
    proposed = maximum
  next_steps = (current * 3 + proposed) / 4 ## i64
  if elapsed_ms > target_ms * 4
    next_steps = proposed
  if next_steps < minimum
    next_steps = minimum
  if next_steps > maximum
    next_steps = maximum
  next_steps

# Wide fleets amortize the serial exact-intake/archive coordinator by making a
# worker epoch long enough to contain useful parallel work.  Small fleets keep
# the historical `--steps` cadence.  Full-fleet measurements put one wide
# coordinator pass near two seconds, so large hosts use multi-second worker
# phases and cap batching at 128 nominal chunks.  The larger ceiling matters
# on very wide hosts: a 500k-step launch sample can be only ~40ms, while the
# measured throughput knee is around 40-50M steps per epoch.
-> ffcp_epoch_target_ms(workers) (i64) i64
  if workers <= 32
    return 0
  3000

-> ffcp_adapt_epoch_steps(current_steps, elapsed_ms, target_ms, nominal_steps) (i64 i64 i64 i64) i64
  current = current_steps ## i64
  nominal = nominal_steps ## i64
  if nominal < 1
    nominal = 1
  if current < nominal
    current = nominal
  if elapsed_ms < 1 || target_ms < 1
    return current
  proposed = current * target_ms / elapsed_ms ## i64
  maximum = nominal * 128 ## i64
  if maximum < nominal
    maximum = nominal
  if proposed < nominal
    proposed = nominal
  if proposed > maximum
    proposed = maximum
  next_steps = (current * 3 + proposed) / 4 ## i64
  # The first wide-host sample is typically an order of magnitude shorter
  # than the desired epoch.  Correct that launch-calibration gap immediately;
  # smoothing is useful only once the coordinator cadence is in range.
  if elapsed_ms * 4 < target_ms || elapsed_ms > target_ms * 4
    next_steps = proposed
  if next_steps < nominal
    next_steps = nominal
  if next_steps > maximum
    next_steps = maximum
  next_steps

# Reproducible per-campaign RNG diversification.  Nonce zero is an exact
# compatibility identity, so existing single-process trajectories do not
# change.  A nonzero nonce is mixed into every caller-provided stream seed;
# ffw_seed_rng performs the subsequent PCG state expansion.
-> ffcp_campaign_seed(base_seed, campaign_nonce) (i64 i64) i64
  if campaign_nonce == 0
    return base_seed
  mask = 4611686018427387903 ## i64
  nonce = campaign_nonce & mask ## i64
  mixed = (nonce * 1000003 + 1442695040888963407) & mask ## i64
  mixed = (mixed ^ (mixed >> 23) ^ (mixed << 17)) & mask
  (base_seed ^ mixed) & mask

-> ffcp_round_step_range(round_steps, workers, output) (i64[] i64 i64[]) i64
  if workers < 1
    output[0] = 0
    output[1] = 0
    return 0
  minimum = round_steps[0] ## i64
  maximum = round_steps[0] ## i64
  lane = 1 ## i64
  while lane < workers
    value = round_steps[lane] ## i64
    if value < minimum
      minimum = value
    if value > maximum
      maximum = value
    lane += 1
  output[0] = minimum
  output[1] = maximum
  maximum

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
