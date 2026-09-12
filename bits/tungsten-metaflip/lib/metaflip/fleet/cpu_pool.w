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
#   2 tuned control-race walk (negative split cadence selects axis-sweep)
#   3 accepted-state cycle-watch walk
#   4 rectangular three-phase island walk (`cadences[lane]` selects the
#     split cadence; the phase quotas derive from the lane's live step count)

use ../rect
use ../rect/cpu_pool

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

# Amortize the serial exact-intake/archive coordinator by making a worker epoch
# long enough to contain useful parallel work. On the normal 12-lane profile,
# 500k steps take only about 10ms and leave workers parked at the round barrier;
# a 250ms target keeps TUI/intake latency interactive while moving the fleet
# beyond the measured throughput knee. Very wide hosts retain multi-second
# phases and the existing 128-chunk cap. Tiny fleets keep historical cadence.
-> ffcp_epoch_target_ms(workers) (i64) i64
  if workers < 8
    return 0
  if workers <= 32
    return 250
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

# Offset finite algebraic-identity portfolios as well as their later worker
# RNG streams.  Without this, separate cloud processes built byte-identical
# +1/+2 shoulder banks even when --seed-nonce differed.  Keep the offset small
# enough that escape identities using nonce multiplication cannot overflow;
# nonce zero remains the historical 0,1,2,... enumeration exactly.
-> ffcp_campaign_identity_nonce(local_nonce, campaign_nonce) (i64 i64) i64
  if campaign_nonce == 0
    return local_nonce
  offset = (ffcp_campaign_seed(70001, campaign_nonce) % 104729) + 1 ## i64
  local_nonce + offset

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

-> ffcp_spawn(state_slots, slot, mode, round_steps, cadences, core_slots, controls, recent, recent_capacity, stats, elapsed_ms, start_channel, done_channel)
  Thread.new ->
    running = 1 ## i64
    phases = i64[3]
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
          if controls[0] >= 0
            result = ffw_walk_tuned(worker_state, round_steps[slot], controls)
          if controls[0] < 0
            result = ffw_walk_axis_sweep_tuned(worker_state, round_steps[slot], controls)
        if mode == 3
          result = ffw_walk_cycle_watch(worker_state, round_steps[slot], recent, recent_capacity, stats)
        if mode == 4
          z = ffrp_campaign_budgets(round_steps[slot], phases) ## i64
          cadence = cadences[slot] ## i64
          if cadence == 2000
            result = ffr_work(worker_state, phases[0])
            result = ffr_walk(worker_state, phases[1])
            result = ffr_wander(worker_state, phases[2])
          if cadence != 2000
            result = ffrcp_work_cadence(worker_state, phases[0], cadence)
            result = ffrcp_walk_cadence(worker_state, phases[1], cadence)
            result = ffrcp_wander_cadence(worker_state, phases[2], cadence)
        elapsed_ms[slot] = ccall("__w_clock_ms") - t0
        # Keep the hot result live through the end of the epoch.  The result is
        # intentionally not sent: all mutable search state already lives in
        # the worker's stable state slot.
        if result < 0
          elapsed_ms[slot] = elapsed_ms[slot]
        done_channel.send(slot)
    0

# Copy the complete continuation, not just its best scheme: RNG, hash chains,
# current state, leases and move counters must all survive a publication.
-> ffcp_copy_words(destination, source, count) (i64[] i64[] i64) i64
  word = 0 ## i64
  while word < count
    destination[word] = source[word]
    word += 1
  count

# Two fixed buffers per lane. Only the worker touches `live` during an epoch;
# coordinator banks/rendering see the stable published buffer. A completion
# transfers ownership through the channel, and that lane stays parked until
# its endpoint has been exact-gated and any reseed has been applied. No endpoint
# or speculative continuation is dropped/coalesced. Other lanes need not park.
+ MetaflipCPUPool
  ro :ready, :threads, :active, :epochs, :completed

  -> new(states, state_size, modes, steps, core_slots, controls, recent, recent_capacity, stats, elapsed, cadences)
    @states = states
    @state_size = state_size
    @workers = states.size()
    if @workers < 1
      raise "metaflip CPU pool: at least one worker is required"
    @modes = modes
    @steps = steps
    @core_slots = core_slots
    @controls = controls
    @stats = stats
    @elapsed = elapsed
    @live = []
    @starts = []
    @threads = []
    @busy = i64[@workers]
    @ready = i64[@workers]
    @epochs = i64[@workers]
    @live_elapsed = i64[@workers]
    @live_steps = i64[@workers]
    @live_core = i64[1]
    @live_controls = i64[7]
    @live_stats = i64[9]
    @done = Channel.new(@workers)
    @active = 0
    @completed = 0
    @stopped = 0
    special_modes = i64[4]
    lane = 0 ## i64
    while lane < @workers
      mode = modes[lane] ## i64
      if mode < 0 || mode > 4
        raise "metaflip CPU pool: invalid worker mode"
      if mode == 4 && (cadences == nil || cadences.size() < @workers)
        raise "metaflip CPU pool: rectangular lanes need a per-lane cadence"
      if mode > 0 && mode < 4
        if special_modes[mode] != 0
          raise "metaflip CPU pool: special lanes must have unique controls"
        special_modes[mode] = 1
      lane += 1
    lane = 0
    while lane < @workers
      @live.push(i64[state_size])
      start = Channel.new(1)
      @starts.push(start)
      @threads.push(ffcp_spawn(@live, lane, modes[lane], @live_steps, cadences, @live_core, @live_controls, recent, recent_capacity, @live_stats, @live_elapsed, start, @done))
      lane += 1

  -> launch_idle()
    self.launch_idle_below(9223372036854775807)

  # Start every parked lane that has completed fewer than `epoch_cap` epochs.
  # A bounded campaign (`--rounds N`) parks each lane at exactly N epochs; a
  # fast lane never runs past the cap while a slower lane finishes its quota.
  -> launch_idle_below(epoch_cap)
    if @stopped != 0
      raise "metaflip CPU pool: cannot restart a stopped pool"
    lane = 0 ## i64
    while lane < @workers
      if @busy[lane] == 0 && @epochs[lane] < epoch_cap
        z = ffcp_copy_words(@live[lane], @states[lane], @state_size)
        @live_steps[lane] = @steps[lane]
        if @modes[lane] == 1
          @live_core[0] = @core_slots[0]
        if @modes[lane] == 2
          z = ffcp_copy_words(@live_controls, @controls, 7)
        if @modes[lane] == 3
          z = ffcp_copy_words(@live_stats, @stats, 9)
        @busy[lane] = 1
        @active += 1
        @starts[lane].send(1)
      lane += 1
    @active

  -> begin_intake()
    lane = 0 ## i64
    while lane < @workers
      @ready[lane] = 0
      @elapsed[lane] = 0
      lane += 1
    @completed = 0
    0

  -> publish(lane)
    if lane < 0 || lane >= @workers || @busy[lane] != 1
      raise "metaflip CPU pool: invalid or duplicate completion"
    z = ffcp_copy_words(@states[lane], @live[lane], @state_size)
    if @modes[lane] == 3
      z = ffcp_copy_words(@stats, @live_stats, 9)
    @elapsed[lane] = @live_elapsed[lane]
    @epochs[lane] = @epochs[lane] + 1
    @busy[lane] = 0
    @ready[lane] = 1
    @active -= 1
    @completed += 1
    lane

  # `all` is reserved for synchronous comparison, explicit generation reset,
  # rank-drop migration, and shutdown. Normal intake waits for one completion
  # then consumes only the already-ready bounded queue, never a straggler.
  -> collect(all)
    if @active > 0
      z = self.publish(@done.recv())
    if all == 1
      while @active > 0
        z = self.publish(@done.recv())
    else
      available = 1 ## i64
      while @active > 0 && available == 1
        result = @done.try_receive()
        if result.received?()
          z = self.publish(result.value())
        else
          available = 0
    @completed

  # Rolling intake with a bounded wait: publish whatever completes within
  # `timeout_ms`, then drain only the already-ready queue.  A coordinator that
  # also polls external producers (GPU epochs, bounded child processes) uses
  # this so neither a slow island nor a slow producer parks the other side.
  -> collect_within(timeout_ms)
    if @active > 0 && @completed == 0
      result = @done.receive_result(timeout_ms)
      if result.received?()
        z = self.publish(result.value())
    available = 1 ## i64
    while @active > 0 && available == 1
      result = @done.try_receive()
      if result.received?()
        z = self.publish(result.value())
      else
        available = 0
    @completed

  -> busy_lane(lane)
    @busy[lane]

  -> lane_epochs(lane)
    @epochs[lane]

  -> minimum_epochs()
    minimum = @epochs[0] ## i64
    lane = 1 ## i64
    while lane < @workers
      if @epochs[lane] < minimum
        minimum = @epochs[lane]
      lane += 1
    minimum

  -> stop_commands()
    if @stopped != 0
      return 0
    if @active != 0
      raise "metaflip CPU pool: drain and intake before stopping"
    lane = 0 ## i64
    while lane < @workers
      @starts[lane].send(0)
      lane += 1
    @stopped = 1
    0
