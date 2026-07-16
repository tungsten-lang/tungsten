# Public-dispatch correctness and timing driver. The runner copies this file
# outside both roots so each compile autoloads core from its explicit root.

use core/small_array
use core/big_array

SMALL_CASES = 11
BIG_CASES = 16
CORPUS_MASK = 15

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> small_fixture(index)
  ccall("w_leaf_small_fixture", index)

-> small_expected(index)
  ccall("w_leaf_small_expected", index)

-> big_fixture(index)
  ccall("w_leaf_big_fixture", index)

-> big_expected(index)
  ccall("w_leaf_big_expected", index)

-> small_raw_size(value)
  ccall_nobox("w_leaf_small_raw_size", value) ## i64

-> big_raw_size(value)
  ccall_nobox("w_leaf_big_raw_size", value) ## i64

-> integer_repr(value)
  ccall("w_leaf_integer_repr", value)

-> dispose_integer(value)
  ccall("w_leaf_dispose_integer", value)

-> release_fixture(value)
  ccall("w_leaf_release_fixture", value)

-> check_integer_result(name, got, expected)
  check_value(name, got, expected)
  expected_repr = integer_repr(expected)
  check_value("[name].repr", integer_repr(got), expected_repr)
  if expected_repr == 0
    check_value("[name].bits", wvalue_bits(got), wvalue_bits(expected))

-> run_small_correctness
  i = 0
  while i < SMALL_CASES
    value = small_fixture(i)
    expected = small_expected(i)
    before = small_raw_size(value)

    got_size = value.size
    got_cap = value.cap
    got_empty = value.empty?
    check_integer_result("small.[i].size", got_size, expected)
    check_integer_result("small.[i].cap", got_cap, expected)
    check_value("small.[i].empty", got_empty, expected == 0)
    check_value("small.[i].empty.bits", wvalue_bits(got_empty),
                wvalue_bits(expected == 0))

    # Native zero-argument handlers historically ignore surplus positional
    # arguments. Public source dispatch must retain that name-only fallback.
    check_value("small.[i].size.extra1", value.size(101), expected)
    check_value("small.[i].size.extra4", value.size(1, 2, 3, 4), expected)
    check_value("small.[i].cap.extra1", value.cap(101), expected)
    check_value("small.[i].cap.extra4", value.cap(1, 2, 3, 4), expected)
    check_value("small.[i].empty.extra1", value.empty?(101), expected == 0)
    check_value("small.[i].empty.extra4", value.empty?(1, 2, 3, 4), expected == 0)
    check_value("small.[i].stable", small_raw_size(value), before)

    dispose_integer(got_size)
    dispose_integer(got_cap)
    dispose_integer(expected)
    release_fixture(value)
    i += 1

  zero = small_fixture(0)
  check_value("small.block.size", zero.size -> 99, nil)
  check_value("small.block.cap", zero.cap -> 99, nil)
  release_fixture(zero)

-> run_big_correctness
  i = 0
  while i < BIG_CASES
    value = big_fixture(i)
    expected = big_expected(i)
    before = big_raw_size(value)
    check_value("big.[i].is-view", ccall("w_leaf_big_view_p", value), true)

    got = value.size
    check_integer_result("big.[i].size", got, expected)
    extra1 = value.size(101)
    extra4 = value.size(1, 2, 3, 4)
    check_integer_result("big.[i].extra1", extra1, expected)
    check_integer_result("big.[i].extra4", extra4, expected)
    check_value("big.[i].stable", big_raw_size(value), before)

    dispose_integer(got)
    dispose_integer(extra1)
    dispose_integer(extra4)
    dispose_integer(expected)
    release_fixture(value)
    i += 1

  zero = big_fixture(0)
  check_value("big.block.size", zero.size -> 99, nil)
  release_fixture(zero)

-> run_correctness
  run_small_correctness()
  run_big_correctness()
  << "correctness: ok (SmallArray 0..255 boundaries; BigArray signed-i64 view headers; exact Int/BigInt/Bool representation; extras, blocks, and receiver stability)"

-> small_corpus
  indexes = [0, 1, 2, 3, 4, 5, 6, 7,
             8, 9, 10, 9, 8, 7, 1, 0]
  values = []
  i = 0
  while i < 16
    values.push(small_fixture(indexes[i]))
    i += 1
  values

-> big_inline_corpus
  indexes = [0, 1, 2, 3, 4, 5, 6, 7,
             8, 11, 12, 8, 7, 6, 1, 0]
  values = []
  i = 0
  while i < 16
    values.push(big_fixture(indexes[i]))
    i += 1
  values

-> big_overflow_corpus
  indexes = [9, 10, 13, 14, 15, 9, 10, 13,
             14, 15, 13, 10, 9, 15, 14, 13]
  values = []
  i = 0
  while i < 16
    values.push(big_fixture(indexes[i]))
    i += 1
  values

-> release_corpus(values)
  i = 0
  while i < values.size
    release_fixture(values[i])
    i += 1

-> clock_ns
  ccall("w_leaf_thread_cpu_ns")

-> finish_timing(started, checksum)
  [clock_ns() - started, checksum]

-> time_small_size(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].size & 0xFF
    i += 1
  finish_timing(started, checksum)

-> time_small_cap(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].cap & 0xFF
    i += 1
  finish_timing(started, checksum)

-> time_small_empty(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].empty? ? 1 : 0
    i += 1
  finish_timing(started, checksum)

-> time_big_inline(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].size & 0xFF
    i += 1
  finish_timing(started, checksum)

-> time_big_overflow(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    result = values[i & CORPUS_MASK].size
    checksum += ccall("w_leaf_consume_integer", result)
    i += 1
  finish_timing(started, checksum)

-> timed_method(method, values, iters)
  if method == "small.size"
    return time_small_size(values, iters)
  if method == "small.cap"
    return time_small_cap(values, iters)
  if method == "small.empty"
    return time_small_empty(values, iters)
  if method == "big.size.inline"
    return time_big_inline(values, iters)
  time_big_overflow(values, iters)

-> run_bench(method, iters, warmup)
  values = nil
  if method.starts_with?("small.")
    values = small_corpus()
  elsif method == "big.size.inline"
    values = big_inline_corpus()
  else
    values = big_overflow_corpus()

  timed_method(method, values, warmup)
  result = timed_method(method, values, iters)
  release_corpus(values)
  ns = result[0] / iters
  << "RESULT|[method]|[ns]|[result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "check"

# A trailing block is passthrough syntax. size/cap return zero in the normal
# correctness fixture and therefore execute Int#each zero times; empty?
# returns Bool, whose lack of each is a historical fatal surface. The runner
# invokes this mode separately and requires the same failure in both roots.
if mode == "empty-block-fatal"
  value = small_fixture(0)
  value.empty? -> 99
  exit(0)

if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench" || args.size < 4
  << "usage: small-big-array-public-hot bench METHOD ITERS WARMUP"
  exit(2)

run_bench(args[1], args[2].to_i, args[3].to_i)
