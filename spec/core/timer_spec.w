-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

fired = Atomic.new(0)
one_shot = Timer.after(~0.01) ->
  fired.increment()
check("timer.after.wait", one_shot.wait() == one_shot)
check("timer.after.once", fired.load() == 1)
check("timer.after.finished", one_shot.finished?() && !one_shot.active?())

cancelled_fired = Atomic.new(0)
cancelled = Timer.after(~1.0) ->
  cancelled_fired.increment()
cancel_started = clock()
check("timer.cancel.claims_waiting", cancelled.cancel())
check("timer.cancel.flag", cancelled.cancelled?())
cancelled.wait()
check("timer.cancel.no_callback", cancelled_fired.load() == 0)
check("timer.cancel.interruptible_wait", clock() - cancel_started < ~0.25)
check("timer.cancel.idempotent_result", !cancelled.cancel())

started = Channel.new(1)
release = Channel.new(1)
in_flight_count = Atomic.new(0)
in_flight = Timer.every(~0.01) ->
  in_flight_count.increment()
  started.send(true)
  release.receive()
started.receive()
check("timer.cancel.in_flight_result", !in_flight.cancel())
release.send(true)
in_flight.wait()
sleep(~0.03)
check("timer.cancel.in_flight_stops_repeat", in_flight_count.load() == 1)

repeat_count = Atomic.new(0)
repeat_ready = Channel.new(1)
repeating = Timer.every(~0.015) ->
  count = repeat_count.increment()
  if count == 3
    repeat_ready.send(true)
repeat_ready.receive()
repeating.cancel()
repeating.wait()
check("timer.every.repeats", repeat_count.load() >= 3)

# A long callback skips expired deadlines instead of triggering a burst of
# catch-up callbacks. The second and third callbacks must still be separated
# by a fresh interval.
skip_count = Atomic.new(0)
skip_times = Channel.new(3)
skip_timer = Timer.every(~0.01) ->
  count = skip_count.increment()
  skip_times.send(clock())
  if count == 1
    sleep(~0.05)
first_tick = skip_times.receive()
second_tick = skip_times.receive()
third_tick = skip_times.receive()
skip_timer.cancel()
skip_timer.wait()
check("timer.every.skips_missed_ticks", third_tick - second_tick > ~0.004)

failed = Timer.after(~0.001) ->
  raise "timer callback boom"
error_surfaced = false
begin
  failed.wait()
rescue error
  error_surfaced = error.to_s.include?("timer callback boom")
check("timer.wait.error", error_surfaced)

timeout = Timer.after(~0.1) -> nil
check("timer.wait.timeout", !timeout.wait(1))
timeout.cancel()
check("timer.wait.after_cancel", timeout.wait(100))

bad_wait_timeout = false
begin
  timeout.wait(-1)
rescue error
  bad_wait_timeout = error.to_s.include?("non-negative Integer")
check("timer.wait.timeout_validation", bad_wait_timeout)

<< "timer_spec: all checks passed"
