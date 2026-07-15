# Production-shaped public-method benchmark. Compile this unchanged source in
# isolated baseline and candidate roots after one unique-name method has passed
# twice. The baseline resolves Array#compact/#dup through its native IC; the
# candidate root must expose the public source body and leave that IC name
# uninstalled.

BATCH_SIZE = 128

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> array_start(value)
  ccall("w_bench_compact_dup_array_start", value)

-> array_cap(value)
  ccall("w_bench_compact_dup_array_cap", value)

-> array_ebits(value)
  ccall("w_bench_compact_dup_array_ebits", value)

-> array_flags(value)
  ccall("w_bench_compact_dup_array_flags", value)

-> expected_cap(size)
  cap = 8
  while cap < size
    cap *= 2
  cap

-> expected_compact(values)
  expected = []
  i = 0
  while i < values.size
    value = values[i]
    if value != nil
      expected.push(value)
    i += 1
  expected

-> check_result(name, got, expected)
  check_value("[name].size", got.size, expected.size)
  check_value("[name].start", array_start(got), 0)
  check_value("[name].ebits", array_ebits(got), 65)
  check_value("[name].flags", array_flags(got), 2)
  check_value("[name].cap", array_cap(got), expected_cap(expected.size))
  i = 0
  while i < expected.size
    got_bits = wvalue_bits(got[i]) ## i64
    expected_bits = wvalue_bits(expected[i]) ## i64
    if got_bits != expected_bits
      fail_check("[name].[i]",
                 "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> dense_values(count)
  values = []
  i = 0
  while i < count
    values.push((i * 17) - 31)
    i += 1
  values

-> sparse_values(count)
  values = []
  i = 0
  while i < count
    values.push((i & 3) == 0 ? nil : (i * 17) - 31)
    i += 1
  values

-> all_nil_values(count)
  values = []
  i = 0
  while i < count
    values.push(nil)
    i += 1
  values

-> typed_values(count)
  values = u16[count]
  i = 0
  while i < count
    values[i] = (i * 977) & 0xFFFF
    i += 1
  values

-> shifted_values(count)
  values = dense_values(count + 9)
  i = 0
  while i < 9
    values.shift
    i += 1
  values

-> workload_values(operation, name)
  if operation == "compact"
    if name == "empty"
      return []
    if name == "all-nil"
      return all_nil_values(64)
    if name == "singleton"
      return [41]
    if name == "small-dense"
      return dense_values(8)
    if name == "small-sparse"
      return sparse_values(8)
    if name == "medium-dense"
      return dense_values(64)
    if name == "medium-sparse"
      return sparse_values(64)
    if name == "large-dense"
      return dense_values(1024)
    if name == "large-sparse"
      return sparse_values(1024)
    if name == "typed"
      return typed_values(64)
    if name == "shifted"
      return shifted_values(64)
  else
    if name == "empty"
      return []
    if name == "singleton"
      return [41]
    if name == "small"
      return dense_values(8)
    if name == "medium"
      return dense_values(64)
    if name == "large"
      return dense_values(1024)
    if name == "typed"
      return typed_values(64)
    if name == "shifted"
      return shifted_values(64)
  nil

-> run_check(operation)
  # Pin the default-capacity representation independently in both processes;
  # retain all later results so a larger old result cannot re-enter the pool
  # and make otherwise-identical paths depend on case order.
  pool_guards = []
  i = 0
  while i < 32
    pool_guards.push([])
    i += 1
  result_guards = []

  cases = []
  cases.push([])
  cases.push([nil])
  cases.push([false])
  cases.push([nil, false, 0, "text", nil, true, ~0.0])

  shifted = sparse_values(20)
  shifted.shift
  shifted.shift
  cases.push(shifted)

  u8s = u8[5]
  u8s[0] = 3
  u8s[1] = 17
  u8s[2] = 129
  u8s[3] = 251
  u8s[4] = 0
  u8s.shift
  cases.push(u8s)

  f64s = f64[4]
  f64s[0] = ~-1.25
  f64s[1] = ~-0.0
  f64s[2] = ~0.0
  f64s[3] = ~4.75
  cases.push(f64s)

  wvalues = w64[5]
  wvalues[0] = nil
  wvalues[1] = false
  wvalues[2] = "text"
  wvalues[3] = nil
  wvalues[4] = 7
  cases.push(wvalues)

  parent = u16[7]
  i = 0
  while i < parent.size
    parent[i] = i * 9000 + 7
    i += 1
  cases.push(parent.slice_view(1, 5))

  i = 0
  while i < cases.size
    values = cases[i]
    if operation == "compact"
      expected = expected_compact(values)
      got = values.compact
    else
      expected = values
      got = values.dup
    check_result("[operation].[i]", got, expected)
    if wvalue_bits(got) == wvalue_bits(values)
      fail_check("[operation].[i].fresh", "public method returned receiver")
    result_guards.push(got)
    if operation == "compact"
      result_guards.push(expected)
    i += 1

  extra = [nil, "kept", false, nil]
  block_log = []
  if operation == "compact"
    extra_result = extra.compact("ignored", 99)
    block_result = extra.compact -> (item)
      block_log.push(item)
    expected = expected_compact(extra)
  else
    extra_result = extra.dup("ignored", 99)
    block_result = extra.dup -> (item)
      block_log.push(item)
    expected = extra
  check_result("[operation].extra", extra_result, expected)
  check_result("[operation].block", block_result, expected)
  # A trailing block on a no-block method iterates the returned value. Pin the
  # public C/source behavior through the result size rather than treating the
  # block as an ignored argument.
  check_value("[operation].result-block", block_log.size, expected.size)
  result_guards.push(extra_result)
  result_guards.push(block_result)
  if operation == "compact"
    result_guards.push(expected)
  << "correctness: ok ([operation] public source/native shape, fresh exact layout, representative typed/shifted/view decoding, extras and result-iteration block)"

-> result_checksum(result)
  checksum = result.size
  if result.size > 0
    checksum += wvalue_bits(result[0]) & 0xFFFF
    checksum += wvalue_bits(result[result.size - 1]) & 0xFFFF
  checksum

-> release_batch(outputs, count)
  ccall("w_bench_compact_dup_release_batch", outputs, count)

-> time_public(values, iters, operation)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    if operation == "compact"
      while i < count
        result = values.compact
        outputs[i] = result
        checksum += result_checksum(result)
        i += 1
    else
      while i < count
        result = values.dup
        outputs[i] = result
        checksum += result_checksum(result)
        i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

args = argv()
mode = args.size > 0 ? args[0] : "check"
operation = args.size > 1 ? args[1] : "compact"
if operation != "compact" && operation != "dup"
  << "operation must be compact or dup"
  exit(2)

if mode == "check"
  run_check(operation)
  exit(0)
if mode != "bench"
  << "mode must be check or bench"
  exit(2)

workload = args.size > 2 ? args[2] : "empty"
values = workload_values(operation, workload)
if values == nil
  << "invalid [operation] workload: [workload]"
  exit(2)
iters = args.size > 3 ? args[3].to_i : 1000
warmup_iters = args.size > 4 ? args[4].to_i : 100
if iters <= 0 || warmup_iters <= 0
  << "iterations and warmup iterations must be positive"
  exit(2)

time_public(values, warmup_iters, operation)
result = time_public(values, iters, operation)
ns = result[0] * 1_000_000_000 / iters
<< "RESULT|public.[operation].[workload]|[ns]|[result[1]]"
