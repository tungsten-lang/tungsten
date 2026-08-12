-> check(name, condition)
  if condition
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

promise = Promise.new()
future = promise.future()
check("promise.interpreted.fulfill", promise.resolve(21))
check("future.interpreted.value", future.value() == 21)

mapped = future.map -> (value) value * 2
check("future.interpreted.map", mapped.value() == 42)

missing_block = false
begin
  Future.async()
rescue error
  missing_block = error.to_s.include?("requires a block")
check("future.async.block_required", missing_block)

bad_timeout = false
begin
  future.wait(-1)
rescue error
  bad_timeout = error.to_s.include?("non-negative Integer")
check("future.wait.timeout_validation", bad_timeout)

<< "future_promise_validation_spec: all checks passed"
