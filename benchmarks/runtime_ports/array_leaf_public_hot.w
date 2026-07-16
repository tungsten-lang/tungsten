# Public-dispatch correctness and timing driver for Array#size/#cap/#empty?/
# #first/#last. The runner copies this file outside both roots; an explicit use
# keeps arbitrary C-produced receivers independent of loader inference.

use core/array

FIXTURE_COUNT = 16
CORPUS_MASK = 15

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture(index)
  ccall("w_array_leaf_fixture", index)

-> ref_size(value)
  ccall("w_array_leaf_ref_size", value)

-> ref_cap(value)
  ccall("w_array_leaf_ref_cap", value)

-> ref_empty(value)
  ccall("w_array_leaf_ref_empty", value)

-> ref_first(value)
  ccall("w_array_leaf_ref_first", value)

-> ref_last(value)
  ccall("w_array_leaf_ref_last", value)

-> integer_repr(value)
  ccall("w_array_leaf_integer_repr", value)

-> dispose_integer(value)
  ccall("w_array_leaf_dispose_integer", value)

-> header_word(value)
  ccall_nobox("w_array_leaf_header_word", value) ## i64

-> size_cap_word(value)
  ccall_nobox("w_array_leaf_size_cap_word", value) ## i64

-> slots_word(value)
  ccall_nobox("w_array_leaf_slots_word", value) ## i64

-> consume(value)
  ccall("w_array_leaf_consume", value)

-> check_exact(name, got, expected)
  check_value(name, got, expected)
  got_repr = integer_repr(got)
  expected_repr = integer_repr(expected)
  check_value("[name].repr", got_repr, expected_repr)
  # BigInts are freshly allocated boxes; compare value + signed limb count.
  # Every other leaf result must preserve the exact WValue representation.
  if expected_repr == 0 || expected_repr == -99
    check_value("[name].bits", wvalue_bits(got), wvalue_bits(expected))

-> dispose_pair(got, expected)
  dispose_integer(got)
  dispose_integer(expected)

-> check_case(value, index)
  before_header = header_word(value)
  before_size_cap = size_cap_word(value)
  before_slots = slots_word(value)

  expected_size = ref_size(value)
  got_size = value.size
  check_exact("case.[index].size", got_size, expected_size)
  extra_size_1 = value.size(101)
  extra_size_4 = value.size(1, 2, 3, 4)
  check_exact("case.[index].size.extra1", extra_size_1, expected_size)
  check_exact("case.[index].size.extra4", extra_size_4, expected_size)

  expected_cap = ref_cap(value)
  got_cap = value.cap
  check_exact("case.[index].cap", got_cap, expected_cap)
  extra_cap_1 = value.cap(101)
  extra_cap_4 = value.cap(1, 2, 3, 4)
  check_exact("case.[index].cap.extra1", extra_cap_1, expected_cap)
  check_exact("case.[index].cap.extra4", extra_cap_4, expected_cap)

  expected_empty = ref_empty(value)
  got_empty = value.empty?
  check_exact("case.[index].empty", got_empty, expected_empty)
  extra_empty_1 = value.empty?(101)
  extra_empty_4 = value.empty?(1, 2, 3, 4)
  check_exact("case.[index].empty.extra1", extra_empty_1, expected_empty)
  check_exact("case.[index].empty.extra4", extra_empty_4, expected_empty)

  expected_first = ref_first(value)
  got_first = value.first
  check_exact("case.[index].first", got_first, expected_first)
  extra_first_1 = value.first(101)
  extra_first_4 = value.first(1, 2, 3, 4)
  check_exact("case.[index].first.extra1", extra_first_1, expected_first)
  check_exact("case.[index].first.extra4", extra_first_4, expected_first)

  expected_last = ref_last(value)
  got_last = value.last
  check_exact("case.[index].last", got_last, expected_last)
  extra_last_1 = value.last(101)
  extra_last_4 = value.last(1, 2, 3, 4)
  check_exact("case.[index].last.extra1", extra_last_1, expected_last)
  check_exact("case.[index].last.extra4", extra_last_4, expected_last)

  if header_word(value) != before_header || size_cap_word(value) != before_size_cap || slots_word(value) != before_slots
    fail_check("case.[index].stable", "receiver flags/ebits/start/size/cap/slots changed")

  dispose_pair(got_size, expected_size)
  dispose_integer(extra_size_1)
  dispose_integer(extra_size_4)
  dispose_pair(got_cap, expected_cap)
  dispose_integer(extra_cap_1)
  dispose_integer(extra_cap_4)
  dispose_pair(got_empty, expected_empty)
  dispose_integer(extra_empty_1)
  dispose_integer(extra_empty_4)
  dispose_pair(got_first, expected_first)
  dispose_integer(extra_first_1)
  dispose_integer(extra_first_4)
  dispose_pair(got_last, expected_last)
  dispose_integer(extra_last_1)
  dispose_integer(extra_last_4)

-> run_correctness
  i = 0
  while i < FIXTURE_COUNT
    check_case(fixture(i), i)
    i += 1

  empty = fixture(0)
  check_value("block.size.empty", empty.size -> 99, nil)
  check_value("block.cap.empty", empty.cap -> 99, nil)
  << "correctness: ok (plain/typed/shifted/view/empty/grown arrays; exact Int/BigInt/Float/Bool/Nil representation; extras, blocks, and receiver stability)"

-> corpus_from_indexes(indexes)
  values = []
  i = 0
  while i < 16
    values.push(fixture(indexes[i]))
    i += 1
  values

-> mixed_corpus
  corpus_from_indexes([0, 1, 2, 3, 4, 5, 6, 7,
                       8, 9, 10, 11, 12, 13, 14, 15])

-> empty_corpus
  corpus_from_indexes([0, 4, 14, 0, 4, 14, 0, 4,
                       14, 4, 0, 14, 4, 0, 14, 0])

-> nonempty_corpus
  corpus_from_indexes([1, 2, 3, 5, 6, 7, 8, 9,
                       10, 11, 12, 13, 15, 1, 5, 8])

-> w64_corpus
  corpus_from_indexes([1, 15, 1, 15, 1, 15, 1, 15,
                       15, 1, 15, 1, 15, 1, 15, 1])

-> typed_corpus
  corpus_from_indexes([5, 8, 9, 10, 11, 13, 5, 8,
                       9, 10, 11, 13, 8, 5, 13, 9])

-> shifted_view_corpus
  corpus_from_indexes([2, 3, 6, 7, 2, 3, 6, 7,
                       7, 6, 3, 2, 7, 6, 3, 2])

-> corpus_for(method)
  if method in ("size.mixed" "cap.mixed")
    return mixed_corpus()
  if method == "empty.empty" || method.ends_with?(".empty")
    return empty_corpus()
  if method == "empty.nonempty"
    return nonempty_corpus()
  if method.ends_with?(".w64")
    return w64_corpus()
  if method.ends_with?(".typed")
    return typed_corpus()
  shifted_view_corpus()

-> clock_ns
  ccall("w_array_leaf_thread_cpu_ns")

-> finish_timing(started, checksum)
  [clock_ns() - started, checksum]

-> time_size(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].size & 0xFF
    i += 1
  finish_timing(started, checksum)

-> time_cap(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].cap & 0xFF
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

-> time_first(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += consume(values[i & CORPUS_MASK].first)
    i += 1
  finish_timing(started, checksum)

-> time_last(values, iters)
  checksum = 0
  i = 0
  started = clock_ns()
  while i < iters
    checksum += consume(values[i & CORPUS_MASK].last)
    i += 1
  finish_timing(started, checksum)

-> timed_method(method, values, iters)
  if method == "size.mixed"
    return time_size(values, iters)
  if method == "cap.mixed"
    return time_cap(values, iters)
  if method.starts_with?("empty.")
    return time_empty(values, iters)
  if method.starts_with?("first.")
    return time_first(values, iters)
  time_last(values, iters)

-> run_bench(method, iters, warmup)
  values = corpus_for(method)
  timed_method(method, values, warmup)
  result = timed_method(method, values, iters)
  # Preserve the full thread-CPU duration. Dividing here rounds an 8-10 ns
  # leaf to whole nanoseconds and turns a one-nanosecond display quantum into
  # a spurious 10-12.5% paired outlier. The runner divides in awk as float.
  << "RESULT|[method]|[result[0]]|[iters]|[result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "check"

# Trailing blocks are passthrough iteration over the method result. Preserve
# the native fatal surfaces for Bool and empty-result Nil separately.
if mode == "empty-block-fatal"
  value = fixture(0)
  value.empty? -> 99
  exit(0)

if mode == "first-block-fatal"
  value = fixture(0)
  value.first -> 99
  exit(0)

if mode == "last-block-fatal"
  value = fixture(0)
  value.last -> 99
  exit(0)

if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench" || args.size < 4
  << "usage: array-leaf-public-hot bench METHOD ITERS WARMUP"
  exit(2)

run_bench(args[1], args[2].to_i, args[3].to_i)
