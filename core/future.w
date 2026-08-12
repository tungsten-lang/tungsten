# Future/Promise shared state and read-only Future facade.
#
# Settlement is claimed exactly once with a sequentially-consistent Atomic.
# Payload publication happens before the terminal state is visible. Every
# waiter registered at settlement receives one completion token; later waiters
# observe the terminal state directly.
#
# Cancellation settles the Future immediately and requests cancellation of an
# attached native worker. Like Thread#kill, cancellation of CPU-only code is
# deferred until the worker reaches a pthread cancellation point. It does not
# roll back side effects and cancelling a composed Future does not cancel its
# parent, since a parent may have other consumers.

+ FutureState
  PENDING = 0
  SETTLING = 1
  FULFILLED = 2
  REJECTED = 3
  CANCELLED = 4
  WAIT_POLL_SECONDS = ~0.001

  -> new
    @status = Atomic.new(PENDING)
    @waiters = Atomic.new(0)
    @signal = Channel.unbounded()
    @lock = Mutex.new()
    @value = nil
    @error = nil
    @worker = nil
    @join_claim = Atomic.new(0)
    @join_done = Atomic.new(0)

  -> fulfill(value)
    __settle(FULFILLED, value, nil)

  -> reject(error)
    __settle(REJECTED, nil, error)

  -> cancel(reason)
    __cancel(reason, true)

  -> cancel_without_interrupt(reason)
    __cancel(reason, false)

  -> __cancel(reason, interrupt_worker)
    if !@status.compare_exchange(PENDING, SETTLING)
      return false

    worker = nil
    @lock.synchronize ->
      @error = reason
      worker = @worker if interrupt_worker
    @status.store(CANCELLED)
    if worker != nil
      worker.kill()
    __notify_waiters()
    true

  -> attach_worker(worker)
    cancel_worker = false
    @lock.synchronize ->
      @worker = worker
      cancel_worker = @status.load() == CANCELLED
    if cancel_worker
      worker.kill()
    self

  -> pending?
    status = @status.load()
    status == PENDING || status == SETTLING

  -> settled?
    !pending?()

  -> fulfilled?
    @status.load() == FULFILLED

  -> rejected?
    @status.load() == REJECTED

  -> cancelled?
    @status.load() == CANCELLED

  -> value
    result = nil
    @lock.synchronize -> result = @value
    result

  -> error
    result = nil
    @lock.synchronize -> result = @error
    result

  -> wait
    if pending?()
      @waiters.increment()
      if pending?()
        @signal.receive()
      @waiters.decrement()
    if !cancelled?()
      __join_worker()
    self

  -> wait(milliseconds)
    if !milliseconds.is_a?(Integer) || milliseconds < 0
      raise "Future wait timeout must be a non-negative Integer in milliseconds"

    deadline = clock() + milliseconds.to_f() / ~1000.0
    while pending?()
      remaining = deadline - clock()
      if remaining <= ~0.0
        return false
      nap = remaining
      if nap > WAIT_POLL_SECONDS
        nap = WAIT_POLL_SECONDS
      sleep(nap)
    true

  # Explicit worker cleanup. Unlike settlement wait, this may block after
  # cancellation when CPU-only code has not reached a cancellation point.
  -> join_worker
    __join_worker()
    self

  -> __settle(status, value, error)
    if !@status.compare_exchange(PENDING, SETTLING)
      return false
    @lock.synchronize ->
      @value = value
      @error = error
    @status.store(status)
    __notify_waiters()
    true

  -> __notify_waiters
    count = @waiters.load()
    i = 0
    while i < count
      @signal.send(true)
      i += 1

  -> __join_worker
    worker = nil
    @lock.synchronize -> worker = @worker
    if worker == nil
      return nil

    if @join_claim.compare_exchange(0, 1)
      worker.join()
      @join_done.store(1)
      return nil

    while @join_done.load() == 0
      sleep(WAIT_POLL_SECONDS)
    nil

# Future — read-only handle for asynchronous settlement and composition.
+ Future
  -> new(@state)

  # Run a block on a native worker and capture its value or error.
  -> .async(&block)
    if block == nil
      raise "Future.async requires a block"
    promise = Promise.new()
    worker = Thread.new ->
      begin
        promise.fulfill(block.call())
      rescue error
        promise.reject(error)
    promise.__attach_worker(worker)
    promise.future()

  -> pending?
    @state.pending?()

  -> settled?
    @state.settled?()

  -> fulfilled?
    @state.fulfilled?()

  -> rejected?
    @state.rejected?()

  -> cancelled?
    @state.cancelled?()

  -> cancel(reason = "Future cancelled")
    @state.cancel(reason)

  -> wait
    @state.wait()
    self

  -> wait(milliseconds)
    @state.wait(milliseconds)

  # Reap the attached worker explicitly. Ordinary wait/value already reap
  # fulfilled and rejected workers; cancelled Futures remain non-blocking.
  -> join
    wait()
    @state.join_worker()
    self

  -> value
    wait()
    __value_or_raise()

  -> value(milliseconds)
    if !wait(milliseconds)
      raise "Future timed out"
    __value_or_raise()

  -> result
    value()

  -> result(milliseconds)
    value(milliseconds)

  # Transform a fulfilled value asynchronously. Rejection and cancellation
  # pass through without invoking the block.
  -> map(&block)
    if block == nil
      raise "Future.map requires a block"
    promise = Promise.new()
    worker = Thread.new ->
      wait()
      if cancelled?()
        promise.__propagate_cancel(@state.error())
      elsif rejected?()
        promise.reject(@state.error())
      else
        begin
          promise.fulfill(block.call(@state.value()))
        rescue error
          promise.reject(error)
    promise.__attach_worker(worker)
    promise.future()

  # Transform a fulfilled value to another Future, flattening its result.
  -> flat_map(&block)
    if block == nil
      raise "Future.flat_map requires a block"
    promise = Promise.new()
    worker = Thread.new ->
      wait()
      if cancelled?()
        promise.__propagate_cancel(@state.error())
      elsif rejected?()
        promise.reject(@state.error())
      else
        begin
          nested = block.call(@state.value())
          if !nested.is_a?(Future)
            raise "Future.flat_map block must return a Future"
          nested.wait()
          if nested.cancelled?()
            promise.__propagate_cancel(nested.__error())
          elsif nested.rejected?()
            promise.reject(nested.__error())
          else
            promise.fulfill(nested.__raw_value())
        rescue error
          promise.reject(error)
    promise.__attach_worker(worker)
    promise.future()

  # Recover a rejected Future. Cancellation remains cancellation.
  -> recover(&block)
    if block == nil
      raise "Future.recover requires a block"
    promise = Promise.new()
    worker = Thread.new ->
      wait()
      if cancelled?()
        promise.__propagate_cancel(@state.error())
      elsif fulfilled?()
        promise.fulfill(@state.value())
      else
        begin
          promise.fulfill(block.call(@state.error()))
        rescue error
          promise.reject(error)
    promise.__attach_worker(worker)
    promise.future()

  # Run cleanup after any settlement, then preserve the original outcome.
  -> finally(&block)
    if block == nil
      raise "Future.finally requires a block"
    promise = Promise.new()
    worker = Thread.new ->
      wait()
      begin
        block.call()
        if cancelled?()
          promise.__propagate_cancel(@state.error())
        elsif rejected?()
          promise.reject(@state.error())
        else
          promise.fulfill(@state.value())
      rescue error
        promise.reject(error)
    promise.__attach_worker(worker)
    promise.future()

  -> __raw_value
    @state.value()

  -> __error
    @state.error()

  -> __value_or_raise
    if cancelled?()
      raise @state.error()
    if rejected?()
      error = @state.error()
      if error == nil
        raise "Future rejected"
      raise error
    @state.value()
