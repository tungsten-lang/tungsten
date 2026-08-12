# Timer — monotonic one-shot and fixed-rate timers.
#
# Timers run callbacks on a native Thread. Repeating timers schedule from the
# previous monotonic deadline, not from callback completion, and skip missed
# ticks instead of running a burst of catch-up callbacks. At most one callback
# is in flight for a Timer.
#
# `cancel` returns true only when it claims the waiting timer before its next
# callback. Once it returns true, that callback cannot start. A false result
# means a callback was already in flight or the timer was already terminal;
# for repeating timers the cancellation request still prevents later ticks.
# Call `wait` to join the worker and re-raise a callback error in the caller.

+ Timer
  WAITING = 0
  CALLBACK = 1
  TERMINAL = 2
  CANCEL_POLL_SECONDS = ~0.005

  ro :interval

  -> .after(delay, &block)
    if block == nil
      raise "Timer.after requires a block"
    Timer.new(Timer.seconds(delay, false), false, block)

  -> .every(interval, &block)
    if block == nil
      raise "Timer.every requires a block"
    Timer.new(Timer.seconds(interval, true), true, block)

  -> .seconds(value, repeating)
    if !(value.is_a?(Int) || value.is_a?(Float) || value.is_a?(Decimal))
      raise "Timer delay must be numeric seconds"

    seconds = value.to_f()
    if seconds < ~0.0 || (repeating && seconds == ~0.0)
      if repeating
        raise "Timer interval must be greater than zero"
      raise "Timer delay must not be negative"
    seconds

  -> new(@interval, @repeating, @callback)
    @gate = Atomic.new(WAITING)
    @cancel_requested = Atomic.new(0)
    @error = nil
    @thread = Thread.new ->
      __run()

  # Request cancellation. True means the next callback was prevented.
  -> cancel
    @cancel_requested.store(1)
    @gate.compare_exchange(WAITING, TERMINAL)

  -> cancelled?
    @cancel_requested.load() != 0

  -> active?
    @gate.load() != TERMINAL

  -> finished?
    @gate.load() == TERMINAL

  # Wait for completion/cancellation and surface any callback error.
  -> wait
    @thread.join()
    if @error != nil
      raise @error
    self

  # Wait at most `milliseconds`. Returns false on timeout, otherwise behaves
  # like wait and returns true (or raises the retained callback error).
  -> wait(milliseconds)
    if !milliseconds.is_a?(Integer) || milliseconds < 0
      raise "Timer wait timeout must be a non-negative Integer in milliseconds"
    if !@thread.join(milliseconds)
      return false
    if @error != nil
      raise @error
    true

  -> __run
    deadline = clock() + @interval
    while true
      if !__wait_until(deadline)
        return nil

      if !@gate.compare_exchange(WAITING, CALLBACK)
        return nil

      begin
        @callback.call()
      rescue error
        @error = error
        @gate.store(TERMINAL)
        return nil

      if !@repeating || @cancel_requested.load() != 0
        @gate.store(TERMINAL)
        return nil

      @gate.store(WAITING)
      deadline += @interval
      now = clock()
      while deadline <= now
        deadline += @interval

  -> __wait_until(deadline)
    while @gate.load() == WAITING
      remaining = deadline - clock()
      if remaining <= ~0.0
        return true
      nap = remaining
      if nap > CANCEL_POLL_SECONDS
        nap = CANCEL_POLL_SECONDS
      sleep(nap)
    false
