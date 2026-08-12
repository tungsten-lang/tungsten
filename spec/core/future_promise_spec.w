-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

promise = Promise.new()
future = promise.future()
check("future.initial.pending", future.pending?() && !future.settled?())
check("promise.fulfill.first", promise.fulfill(42))
check("promise.fulfill.once", !promise.fulfill(43) && !promise.reject("late"))
check("future.fulfilled", future.fulfilled?() && future.settled?())
check("future.value", future.value() == 42)

rejected_promise = Promise.new()
rejected_promise.reject("future boom")
rejected = rejected_promise.future()
rejected_error = false
begin
  rejected.value()
rescue error
  rejected_error = error.to_s.include?("future boom")
check("future.rejected.error", rejected.rejected?() && rejected_error)

async = Future.async -> 6 * 7
check("future.async.value", async.value() == 42)

async_error = Future.async -> raise "async boom"
async_error_seen = false
begin
  async_error.value()
rescue error
  async_error_seen = error.to_s.include?("async boom")
check("future.async.error", async_error_seen)

delayed_promise = Promise.new()
delayed = delayed_promise.future()
waiter_results = Channel.new(4)
waiters = []
i = 0
while i < 4
  waiter = Thread.new -> waiter_results.send(delayed.value())
  waiters.push(waiter)
  i += 1
sleep(~0.01)
delayed_promise.fulfill(9)
sum = 0
i = 0
while i < 4
  sum += waiter_results.receive()
  waiters[i].join()
  i += 1
check("future.multiple_waiters", sum == 36)

timeout_promise = Promise.new()
timeout_future = timeout_promise.future()
check("future.wait.timeout", !timeout_future.wait(2))
timed_value_error = false
begin
  timeout_future.value(2)
rescue error
  timed_value_error = error.to_s.include?("timed out")
check("future.value.timeout", timed_value_error)
timeout_promise.fulfill(5)
check("future.wait.after_settle", timeout_future.wait(0) && timeout_future.value() == 5)

map_source = Future.async -> 5
mapped = map_source.map -> (value) value * 2
check("future.map", mapped.value() == 10)

flat_source = Future.async -> 7
flat = flat_source.flat_map -> (value)
  nested = Promise.new()
  nested.fulfill(value + 1)
  nested.future()
check("future.flat_map", flat.value() == 8)

recover_source = Future.async -> raise "recover me"
recovered = recover_source.recover -> (error) error.to_s.include?("recover me") ? 11 : 0
check("future.recover", recovered.value() == 11)

mapped_reject_source = Promise.new()
mapped_reject = mapped_reject_source.future().map -> (value) value + 1
mapped_reject_source.reject("mapped rejection")
mapped_reject_seen = false
begin
  mapped_reject.value()
rescue error
  mapped_reject_seen = error.to_s.include?("mapped rejection")
check("future.map.rejection_passthrough", mapped_reject_seen)

mapped_cancel_source = Promise.new()
mapped_cancel = mapped_cancel_source.future().map -> (value) value + 1
mapped_cancel_source.cancel("parent cancelled")
mapped_cancel.wait()
check("future.map.cancellation_passthrough", mapped_cancel.cancelled?())

cleanup_count = Atomic.new(0)
cleanup_source = Future.async -> 13
cleaned = cleanup_source.finally -> cleanup_count.increment()
check("future.finally.value", cleaned.value() == 13)
check("future.finally.runs", cleanup_count.load() == 1)

cancel_side_effect = Atomic.new(0)
cancellable = Future.async ->
  sleep(~1.0)
  cancel_side_effect.increment()
check("future.cancel.first", cancellable.cancel("stopped"))
check("future.cancel.once", !cancellable.cancel())
cancel_error = false
begin
  cancellable.value()
rescue error
  cancel_error = error.to_s.include?("stopped")
check("future.cancel.error", cancellable.cancelled?() && cancel_error)
sleep(~0.02)
check("future.cancel.worker", cancel_side_effect.load() == 0)
cancellable.join()

race = Promise.new()
wins = Atomic.new(0)
racers = []
i = 0
while i < 12
  value = i
  racer = Thread.new ->
    if race.fulfill(value)
      wins.increment()
  racers.push(racer)
  i += 1
i = 0
while i < racers.size
  racers[i].join()
  i += 1
check("promise.race.exactly_once", wins.load() == 1 && race.future().fulfilled?())

<< "future_promise_spec: all checks passed"
