# Strict same-binary Array#compact / Array#dup migration harness. The __c_*
# methods call benchmark-only mirrors of the installed ICs; v1 is the literal
# source translation and v2 hoists the immutable receiver size. Public methods
# remain the production C handlers throughout this first gate.

use array_compact_dup_candidates

BATCH_SIZE = 128

+ CompactDupProbe
  -> new(@label)

+ Array
  -> __c_compact
    ccall("w_ref_array_compact", self)

  -> __c_dup
    ccall("w_ref_array_dup", self)

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

-> expected_default_cap(size)
  cap = 8
  while cap < size
    cap *= 2
  cap

-> check_result(name, got, expected)
  check_value("[name].size", got.size, expected.size)
  check_value("[name].start", array_start(got), 0)
  check_value("[name].ebits", array_ebits(got), 65)
  check_value("[name].flags", array_flags(got), 2)
  check_value("[name].cap-vs-c", array_cap(got), array_cap(expected))
  check_value("[name].cap-default-growth", array_cap(got),
              expected_default_cap(expected.size))
  i = 0
  while i < expected.size
    got_bits = wvalue_bits(got[i]) ## i64
    expected_bits = wvalue_bits(expected[i]) ## i64
    if got_bits != expected_bits
      fail_check("[name].item.[i]",
                 "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> check_fresh_independent(name, receiver, results)
  all = [receiver]
  i = 0
  while i < results.size
    all.push(results[i])
    i += 1
  i = 0
  while i < all.size
    j = i + 1
    while j < all.size
      if wvalue_bits(all[i]) == wvalue_bits(all[j])
        fail_check("[name].fresh", "paths [i] and [j] alias")
      j += 1
    i += 1

-> check_receiver_unchanged(name, values, source_size, source_start,
                            source_cap, source_ebits, source_flags,
                            source_oracle)
  check_value("[name].receiver.size", values.size, source_size)
  check_value("[name].receiver.start", array_start(values), source_start)
  check_value("[name].receiver.cap", array_cap(values), source_cap)
  check_value("[name].receiver.ebits", array_ebits(values), source_ebits)
  check_value("[name].receiver.flags", array_flags(values), source_flags)
  check_value("[name].receiver.oracle-size", values.size, source_oracle.size)
  i = 0
  while i < values.size
    got_bits = wvalue_bits(values[i]) ## i64
    expected_bits = wvalue_bits(source_oracle[i]) ## i64
    if got_bits != expected_bits
      fail_check("[name].receiver.item.[i]",
                 "got-bits=[got_bits] expected-bits=[expected_bits]")
    i += 1

-> check_operation(name, values, operation, result_guards)
  source_size = values.size
  source_start = array_start(values)
  source_cap = array_cap(values)
  source_ebits = array_ebits(values)
  source_flags = array_flags(values)

  # compact needs a separate unfiltered snapshot; dup's C result is already
  # that exact shallow snapshot. Every returned Array is retained so no later
  # case can observe a recycled capacity from an earlier case.
  source_oracle = nil
  if operation == "compact"
    source_oracle = values.__c_dup
    c_result = values.__c_compact
    v1_result = values.__w_compact_v1
    v2_result = values.__w_compact_v2
    public_result = values.compact
  else
    c_result = values.__c_dup
    source_oracle = c_result
    v1_result = values.__w_dup_v1
    v2_result = values.__w_dup_v2
    public_result = values.dup

  check_result("[name].[operation].v1", v1_result, c_result)
  check_result("[name].[operation].v2", v2_result, c_result)
  check_result("[name].[operation].public", public_result, c_result)
  check_result("[name].[operation].c", c_result, c_result)

  independent = [c_result, v1_result, v2_result, public_result]
  if operation == "compact"
    independent.push(source_oracle)
  check_fresh_independent("[name].[operation]", values, independent)
  check_receiver_unchanged("[name].[operation]", values, source_size,
                           source_start, source_cap, source_ebits,
                           source_flags, source_oracle)

  result_guards.push(c_result)
  result_guards.push(v1_result)
  result_guards.push(v2_result)
  result_guards.push(public_result)
  if operation == "compact"
    result_guards.push(source_oracle)

-> check_case(name, values, result_guards)
  check_operation(name, values, "compact", result_guards)
  check_operation(name, values, "dup", result_guards)

-> poly_sequence(count, nil_period = 0)
  values = []
  i = 0
  while i < count
    if nil_period > 0 && (i % nil_period) == 0
      values.push(nil)
    elsif (i & 3) == 0
      values.push(i - 17)
    elsif (i & 3) == 1
      values.push("value-" + i.to_s)
    elsif (i & 3) == 2
      values.push((i & 1) == 0)
    else
      values.push(~1.25 + i)
    i += 1
  values

-> append_typed_cases(cases)
  cases.push(["typed-empty-u8", u8[0]])

  bools = bool[5]
  bools[0] = true
  bools[1] = false
  bools[2] = true
  bools[3] = false
  bools[4] = true
  cases.push(["typed-bool", bools])

  u1s = u1[5]
  u1s[0] = 1
  u1s[1] = 0
  u1s[2] = 1
  u1s[3] = 1
  u1s[4] = 0
  cases.push(["typed-u1", u1s])

  u4s = u4[5]
  u4s[0] = 0
  u4s[1] = 1
  u4s[2] = 7
  u4s[3] = 9
  u4s[4] = 15
  cases.push(["typed-u4", u4s])

  i4s = i4[5]
  i4s[0] = -8
  i4s[1] = -1
  i4s[2] = 0
  i4s[3] = 1
  i4s[4] = 7
  cases.push(["typed-i4", i4s])

  u8s = u8[6]
  u8s[0] = 3
  u8s[1] = 17
  u8s[2] = 129
  u8s[3] = 251
  u8s[4] = 0
  u8s[5] = 255
  u8s.shift
  cases.push(["typed-u8-shifted", u8s])

  i8s = i8[5]
  i8s[0] = -128
  i8s[1] = -7
  i8s[2] = 0
  i8s[3] = 17
  i8s[4] = 127
  cases.push(["typed-i8", i8s])

  u16s = u16[5]
  u16s[0] = 0
  u16s[1] = 17
  u16s[2] = 32768
  u16s[3] = 65534
  u16s[4] = 65535
  cases.push(["typed-u16", u16s])

  i16s = i16[5]
  i16s[0] = -32768
  i16s[1] = -11
  i16s[2] = 0
  i16s[3] = 19
  i16s[4] = 32767
  cases.push(["typed-i16", i16s])

  u32s = u32[5]
  u32s[0] = 0
  u32s[1] = 19
  u32s[2] = 1_000_000
  u32s[3] = 4_000_000_000
  u32s[4] = 4_294_967_295
  cases.push(["typed-u32", u32s])

  # Preserve the runtime's current shared ebits=32 decoder for i32.
  i32s = i32[5]
  i32s[0] = -2_000_000_000
  i32s[1] = -13
  i32s[2] = 0
  i32s[3] = 17
  i32s[4] = 2_000_000_000
  cases.push(["typed-i32", i32s])

  u64s = u64[5]
  u64s[0] = 0
  u64s[1] = 23
  u64s[2] = 1_000_000_000
  u64s[3] = 2_000_000_000
  u64s[4] = 4_000_000_000
  cases.push(["typed-u64", u64s])

  i64s = i64[5]
  i64s[0] = -2_000_000_000
  i64s[1] = -17
  i64s[2] = 0
  i64s[3] = 29
  i64s[4] = 2_000_000_000
  cases.push(["typed-i64", i64s])

  f32s = f32[5]
  f32s[0] = ~-3.75
  f32s[1] = ~-0.0
  f32s[2] = ~0.0
  f32s[3] = ~1.5
  f32s[4] = ~2.25
  cases.push(["typed-f32", f32s])

  f64s = f64[5]
  f64s[0] = ~-4.75
  f64s[1] = ~-0.0
  f64s[2] = ~0.0
  f64s[3] = ~1.25
  f64s[4] = ~2.5
  cases.push(["typed-f64", f64s])

  bf16s = bf16[5]
  bf16s[0] = ~-4.0
  bf16s[1] = ~-0.0
  bf16s[2] = ~0.0
  bf16s[3] = ~1.5
  bf16s[4] = ~2.0
  cases.push(["typed-bf16", bf16s])

  wvalues = w64[6]
  wvalues[0] = nil
  wvalues[1] = false
  wvalues[2] = "text"
  wvalues[3] = 41
  wvalues[4] = nil
  wvalues[5] = true
  cases.push(["typed-w64-with-nil", wvalues])

-> check_extra_and_block_surface(result_guards)
  values = [nil, "kept", false, 7, nil]

  c_compact = values.__c_compact("ignored", 99, nil)
  v1_compact = values.__w_compact_v1("ignored", 99, nil)
  v2_compact = values.__w_compact_v2("ignored", 99, nil)
  public_compact = values.compact("ignored", 99, nil)
  check_result("extra.compact.v1", v1_compact, c_compact)
  check_result("extra.compact.v2", v2_compact, c_compact)
  check_result("extra.compact.public", public_compact, c_compact)

  c_dup = values.__c_dup("ignored", 99, nil)
  v1_dup = values.__w_dup_v1("ignored", 99, nil)
  v2_dup = values.__w_dup_v2("ignored", 99, nil)
  public_dup = values.dup("ignored", 99, nil)
  check_result("extra.dup.v1", v1_dup, c_dup)
  check_result("extra.dup.v2", v2_dup, c_dup)
  check_result("extra.dup.public", public_dup, c_dup)

  block_log = []
  block_c_compact = values.__c_compact -> (item)
    block_log.push(item)
  check_value("implicit-each after C compact", block_log.size,
              block_c_compact.size)
  block_v2_compact = values.__w_compact_v2 -> (item)
    block_log.push(item)
  check_value("implicit-each after W compact", block_log.size,
              block_c_compact.size * 2)
  block_public_compact = values.compact -> (item)
    block_log.push(item)
  check_value("implicit-each after public compact", block_log.size,
              block_c_compact.size * 3)
  check_result("block.compact.v2", block_v2_compact, block_c_compact)
  check_result("block.compact.public", block_public_compact, block_c_compact)

  block_c_dup = values.__c_dup -> (item)
    block_log.push(item)
  check_value("implicit-each after C dup", block_log.size,
              block_c_compact.size * 3 + block_c_dup.size)
  block_v2_dup = values.__w_dup_v2 -> (item)
    block_log.push(item)
  check_value("implicit-each after W dup", block_log.size,
              block_c_compact.size * 3 + block_c_dup.size * 2)
  block_public_dup = values.dup -> (item)
    block_log.push(item)
  check_value("implicit-each after public dup", block_log.size,
              block_c_compact.size * 3 + block_c_dup.size * 3)
  check_result("block.dup.v2", block_v2_dup, block_c_dup)
  check_result("block.dup.public", block_public_dup, block_c_dup)
  check_value("implicit-each block invocation count", block_log.size,
              block_c_compact.size * 3 + block_c_dup.size * 3)

  [c_compact, v1_compact, v2_compact, public_compact,
   c_dup, v1_dup, v2_dup, public_dup,
   block_c_compact, block_v2_compact, block_public_compact,
   block_c_dup, block_v2_dup, block_public_dup].each -> (result)
    result_guards.push(result)

-> run_correctness
  # Drain the bounded ordinary-Array pool and retain every guard. This makes
  # each result begin at default cap 8 rather than inheriting an old large
  # capacity, so growth boundaries remain exactly observable.
  pool_guards = []
  i = 0
  while i < 32
    pool_guards.push([])
    i += 1

  result_guards = []
  cases = []
  cases.push(["empty", []])
  cases.push(["singleton-nil", [nil]])
  cases.push(["singleton-false", [false]])
  cases.push(["mixed-nil-false", [nil, false, 0, "x", nil, true, ~0.0]])

  shared = CompactDupProbe.new("shared")
  other = CompactDupProbe.new("shared")
  cases.push(["shallow-object-identity", [shared, nil, shared, other]])

  [7, 8, 9, 15, 16, 17, 32, 33].each -> (count)
    cases.push(["capacity-[count]", poly_sequence(count)])
    cases.push(["capacity-sparse-[count]", poly_sequence(count, 3)])

  shifted = poly_sequence(20, 4)
  shifted.shift
  shifted.shift
  cases.push(["shifted-polymorphic", shifted])

  grown_shifted = poly_sequence(40, 5)
  i = 0
  while i < 9
    grown_shifted.shift
    i += 1
  cases.push(["grown-shifted-polymorphic", grown_shifted])

  plain_parent = ["discard", nil, "a", false, "b", nil, "tail"]
  cases.push(["borrowed-polymorphic-view", plain_parent.slice_view(1, 5)])

  typed_parent = u16[7]
  i = 0
  while i < typed_parent.size
    typed_parent[i] = i * 9000 + 17
    i += 1
  cases.push(["borrowed-typed-view", typed_parent.slice_view(2, 4)])
  append_typed_cases(cases)

  i = 0
  while i < cases.size
    check_case(cases[i][0], cases[i][1], result_guards)
    i += 1
  check_extra_and_block_surface(result_guards)

  # Mutating one fresh result must not affect its receiver or a sibling path.
  source = [1, nil, 2]
  left = source.__w_dup_v2
  right = source.__c_dup
  left.push(99)
  check_value("mutation.source-size", source.size, 3)
  check_value("mutation.sibling-size", right.size, 3)
  check_value("mutation.result-size", left.size, 4)
  result_guards.push(left)
  result_guards.push(right)

  << "correctness: ok ([cases.size] input families; C/v1/v2/public compact+dup, exact bits/layout/capacity, fresh shallow copies, unchanged receivers, polymorphic/typed/shifted/borrowed arrays, ignored extras, result-iteration blocks, and mutation independence)"

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

-> result_checksum(result)
  checksum = result.size
  if result.size > 0
    checksum += wvalue_bits(result[0]) & 0xFFFF
    checksum += wvalue_bits(result[result.size - 1]) & 0xFFFF
  checksum

-> release_batch(outputs, count)
  ccall("w_bench_compact_dup_release_batch", outputs, count)

-> time_compact_c(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__c_compact
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_compact_v1(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__w_compact_v1
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_compact_v2(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__w_compact_v2
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_dup_c(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__c_dup
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_dup_v1(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__w_dup_v1
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_dup_v2(values, iters)
  outputs = w64[BATCH_SIZE]
  elapsed = 0
  checksum = 0
  completed = 0
  while completed < iters
    count = iters - completed
    count = BATCH_SIZE if count > BATCH_SIZE
    i = 0
    started = clock()
    while i < count
      result = values.__w_dup_v2
      outputs[i] = result
      checksum += result_checksum(result)
      i += 1
    elapsed += clock() - started
    release_batch(outputs, count)
    completed += count
  [elapsed, checksum]

-> time_c(values, iters, operation)
  if operation == "compact"
    return time_compact_c(values, iters)
  time_dup_c(values, iters)

-> time_candidate(values, iters, operation, path)
  if operation == "compact"
    if path == "v1"
      return time_compact_v1(values, iters)
    return time_compact_v2(values, iters)
  if path == "v1"
    return time_dup_v1(values, iters)
  time_dup_v2(values, iters)

-> combine_results(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(values, iters, parity, operation, path, workload, emit = true)
  if parity == 0
    c_first = time_c(values, iters, operation)
    w_first = time_candidate(values, iters, operation, path)
    w_second = time_candidate(values, iters, operation, path)
    c_second = time_c(values, iters, operation)
  else
    w_first = time_candidate(values, iters, operation, path)
    c_first = time_c(values, iters, operation)
    c_second = time_c(values, iters, operation)
    w_second = time_candidate(values, iters, operation, path)

  c_result = combine_results(c_first, c_second)
  w_result = combine_results(w_first, w_second)
  if c_result[1] != w_result[1]
    fail_check("benchmark.[operation].[path].[workload]",
               "C checksum=[c_result[1]] W checksum=[w_result[1]]")
  if emit
    denominator = iters * 2
    c_ns = c_result[0] * 1_000_000_000 / denominator
    w_ns = w_result[0] * 1_000_000_000 / denominator
    << "RESULT|[operation].[path].[workload]|[c_ns]|[w_ns]|[w_result[0] / c_result[0]]|[c_result[1]]"

-> run_batch_smoke
  values = sparse_values(64)
  iters = BATCH_SIZE + 13
  c_compact = time_compact_c(values, iters)
  v1_compact = time_compact_v1(values, iters)
  v2_compact = time_compact_v2(values, iters)
  c_dup = time_dup_c(values, iters)
  v1_dup = time_dup_v1(values, iters)
  v2_dup = time_dup_v2(values, iters)
  check_value("batch.compact.v1", v1_compact[1], c_compact[1])
  check_value("batch.compact.v2", v2_compact[1], c_compact[1])
  check_value("batch.dup.v1", v1_dup[1], c_dup[1])
  check_value("batch.dup.v2", v2_dup[1], c_dup[1])
  << "batch cleanup smoke: ok ([iters] results/path; full + partial batch)"

args = argv()
mode = args.size > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
  run_batch_smoke()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

operation = args.size > 1 ? args[1] : "compact"
if operation != "compact" && operation != "dup"
  << "operation must be compact or dup"
  exit(2)

workload = args.size > 2 ? args[2] : "medium-dense"
values = workload_values(operation, workload)
if values == nil
  << "invalid [operation] workload: [workload]"
  exit(2)

iters = args.size > 3 ? args[3].to_i : 1_000
warmup_iters = args.size > 4 ? args[4].to_i : 100
parity = args.size > 5 ? args[5].to_i : 0
path = args.size > 6 ? args[6] : "v2"
if iters <= 0 || warmup_iters <= 0
  << "iterations and warmup iterations must be positive"
  exit(2)
if parity != 0 && parity != 1
  << "sample parity must be 0 or 1"
  exit(2)
if path != "v1" && path != "v2"
  << "candidate path must be v1 or v2"
  exit(2)

run_pair(values, warmup_iters, parity, operation, path, workload, false)
run_pair(values, iters, parity, operation, path, workload)
