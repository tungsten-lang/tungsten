-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

missing_after_block = false
begin
  Timer.after(1)
rescue error
  missing_after_block = error.to_s.include?("requires a block")
check("timer.after.block_required", missing_after_block)

missing_every_block = false
begin
  Timer.every(1)
rescue error
  missing_every_block = error.to_s.include?("requires a block")
check("timer.every.block_required", missing_every_block)

negative_delay = false
begin
  Timer.after(-1) -> nil
rescue error
  negative_delay = error.to_s.include?("must not be negative")
check("timer.after.negative", negative_delay)

zero_interval = false
begin
  Timer.every(0) -> nil
rescue error
  zero_interval = error.to_s.include?("greater than zero")
check("timer.every.zero", zero_interval)

bad_type = false
begin
  Timer.after("1") -> nil
rescue error
  bad_type = error.to_s.include?("must be numeric")
check("timer.delay.type", bad_type)

interpreted_fired = Atomic.new(0)
interpreted_timer = Timer.after(0) ->
  interpreted_fired.increment()
interpreted_timer.wait()
check("timer.after.interpreted", interpreted_fired.load() == 1)

<< "timer_validation_spec: all checks passed"
