# Public-dispatch correctness and timing driver for BigArray#cap/#empty?.
# The runner copies this outside both roots and links the same C fixture file
# into matched release/LTO binaries; every timed operation is a public call.

use core/big_array

CORPUS_MASK = 15

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture(index)
  ccall("w_bace_fixture", index)

-> expected_cap(index)
  ccall("w_bace_expected_cap", index)

-> expected_empty(index)
  ccall("w_bace_expected_empty", index)

-> raw_size(value)
  ccall_nobox("w_bace_raw_size", value) ## i64

-> raw_cap(value)
  ccall_nobox("w_bace_raw_cap", value) ## i64

-> integer_repr(value)
  ccall("w_bace_integer_repr", value)

-> dispose_integer(value)
  ccall("w_bace_dispose_integer", value)

-> release_fixture(value)
  ccall("w_bace_release", value)

-> check_integer_result(name, got, expected)
  check_value(name, got, expected)
  expected_repr = integer_repr(expected)
  check_value("[name].repr", integer_repr(got), expected_repr)
  if expected_repr == 0
    check_value("[name].bits", wvalue_bits(got), wvalue_bits(expected))

-> run_correctness
  count = ccall("w_bace_case_count")
  i = 0
  while i < count
    value = fixture(i)
    cap_expected = expected_cap(i)
    empty_expected = expected_empty(i)
    size_before = raw_size(value)
    cap_before = raw_cap(value)

    check_value("case.[i].view", ccall("w_bace_view_p", value), true)

    got_cap = value.cap
    got_empty = value.empty?
    check_integer_result("case.[i].cap", got_cap, cap_expected)
    check_value("case.[i].empty", got_empty, empty_expected)
    check_value("case.[i].empty.bits", wvalue_bits(got_empty),
                wvalue_bits(empty_expected))

    # The removed C handlers ignored surplus positional arguments. Source
    # dispatch's name-only fallback must preserve that public behavior.
    cap_extra1 = value.cap(101)
    cap_extra4 = value.cap(1, 2, 3, 4)
    check_integer_result("case.[i].cap.extra1", cap_extra1, cap_expected)
    check_integer_result("case.[i].cap.extra4", cap_extra4, cap_expected)
    check_value("case.[i].empty.extra1", value.empty?(101), empty_expected)
    check_value("case.[i].empty.extra4", value.empty?(1, 2, 3, 4),
                empty_expected)

    check_value("case.[i].size.stable", raw_size(value), size_before)
    check_value("case.[i].cap.stable", raw_cap(value), cap_before)

    dispose_integer(got_cap)
    dispose_integer(cap_extra1)
    dispose_integer(cap_extra4)
    dispose_integer(cap_expected)
    release_fixture(value)
    i += 1

  # A trailing block is passthrough syntax. A zero cap executes Int#each zero
  # times and historically yields nil. Bool#each remains the separate fatal
  # surface exercised by the runner's empty-block-fatal mode.
  zero = fixture(0)
  check_value("block.cap.zero", zero.cap -> 99, nil)
  release_fixture(zero)

  << "correctness: ok (signed-i64 cap boundaries; exact Int/BigInt/Bool representation; zero/nonzero size; extras, blocks, views, and stable headers)"

-> fixture_corpus(indexes)
  values = []
  i = 0
  while i < indexes.size
    values.push(fixture(indexes[i]))
    i += 1
  values

-> corpus_for(method)
  if method == "cap.inline.valid"
    return fixture_corpus([0, 1, 2, 3, 4, 5, 4, 3,
                           2, 1, 0, 5, 4, 2, 1, 0])
  if method == "cap.inline.synthetic"
    return fixture_corpus([6, 7, 8, 9, 6, 7, 8, 9,
                           7, 9, 6, 8, 9, 7, 8, 6])
  if method == "cap.overflow.positive"
    return fixture_corpus([10, 11, 12, 10, 11, 12, 10, 12,
                           11, 10, 12, 11, 12, 10, 11, 12])
  if method == "cap.overflow.negative"
    return fixture_corpus([13, 14, 15, 13, 14, 15, 13, 15,
                           14, 13, 15, 14, 15, 13, 14, 15])
  if method == "empty.zero"
    return fixture_corpus([0, 16, 20, 21, 0, 16, 20, 21,
                           21, 20, 16, 0, 20, 0, 21, 16])
  if method == "empty.nonzero.positive"
    return fixture_corpus([1, 2, 3, 4, 5, 6, 7, 10,
                           11, 12, 17, 18, 1, 5, 7, 18])
  fixture_corpus([8, 9, 13, 14, 15, 19, 8, 19,
                  15, 13, 9, 14, 19, 8, 15, 9])

-> release_corpus(values)
  i = 0
  while i < values.size
    release_fixture(values[i])
    i += 1

-> clock_ns
  ccall("w_bace_thread_cpu_ns")

-> finish_timing(started, checksum)
  [clock_ns() - started, checksum]

-> time_cap_inline(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].cap & 0xFF
    i += 1
  finish_timing(started, checksum)

-> time_cap_overflow(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    result = values[i & CORPUS_MASK].cap
    checksum += ccall("w_bace_consume_integer", result)
    i += 1
  finish_timing(started, checksum)

-> time_empty(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].empty? ? 1 : 0
    i += 1
  finish_timing(started, checksum)

-> timed_method(method, values, iters)
  if method.starts_with?("cap.overflow.")
    return time_cap_overflow(values, iters)
  if method.starts_with?("cap.")
    return time_cap_inline(values, iters)
  time_empty(values, iters)

-> run_bench(method, iters, warmup)
  values = corpus_for(method)
  timed_method(method, values, warmup)
  result = timed_method(method, values, iters)
  release_corpus(values)
  ns = result[0] / iters
  << "RESULT|[method]|[ns]|[result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "check"

if mode == "empty-block-fatal"
  value = fixture(0)
  value.empty? -> 99
  exit(0)

if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench" || args.size < 4
  << "usage: big-array-cap-empty-revisit-public bench METHOD ITERS WARMUP"
  exit(2)

run_bench(args[1], args[2].to_i, args[3].to_i)
