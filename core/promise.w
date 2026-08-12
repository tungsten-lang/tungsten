# Promise — writable, exactly-once settlement for a read-only Future.

+ Promise
  -> new
    @state = FutureState.new()
    @future = Future.new(@state)

  -> future
    @future

  -> fulfill(value)
    @state.fulfill(value)

  -> resolve(value)
    fulfill(value)

  -> reject(error)
    @state.reject(error)

  -> cancel(reason = "Future cancelled")
    @state.cancel(reason)

  -> settled?
    @state.settled?()

  -> __attach_worker(worker)
    @state.attach_worker(worker)
    self

  # Composition workers propagate cancellation after they wake; do not ask a
  # worker to cancel its own pthread while it is publishing that result.
  -> __propagate_cancel(reason)
    @state.cancel_without_interrupt(reason)
