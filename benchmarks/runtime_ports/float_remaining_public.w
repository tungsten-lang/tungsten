# Public-dispatch gate for Float#floor/#ceil/#round/#sqrt/#sq.
#
# This shared workload deliberately has no `use` directive. The baseline must
# reach its C IC rows; the candidate must autoload Float and reach source.

CASE_COUNT = 32
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 40_000_000
DEFAULT_WARMUP = 1_000_000

-> float_case(index)
  ccall("w_float_remaining_case", index)

-> float_value?(value)
  ccall("w_float_remaining_float_p", value)

-> integer_value?(value)
  ccall("w_float_remaining_integer_p", value)

-> ref_floor(value)
  ccall("w_float_remaining_ref_floor", value)

-> ref_ceil(value)
  ccall("w_float_remaining_ref_ceil", value)

-> ref_round(value)
  ccall("w_float_remaining_ref_round", value)

-> ref_sqrt(value)
  ccall("w_float_remaining_ref_sqrt", value)

-> ref_sq(value)
  ccall("w_float_remaining_ref_sq", value)

-> fail_check(method, index, path, got, expected)
  << "FAIL [method] case=[index] [path] got=[got] expected=[expected]"
  exit(1)

-> check_integer_result(method, index, path, got, expected)
  if !integer_value?(got)
    fail_check(method, index, "[path] type", got, "Integer")
  if got != expected
    fail_check(method, index, path, got, expected)

-> check_float_result(method, index, path, got, expected)
  if !float_value?(got)
    fail_check(method, index, "[path] type", got, "Float")
  got_bits = wvalue_bits(got)
  expected_bits = wvalue_bits(expected)
  if got_bits != expected_bits
    fail_check(method, index, path, got_bits, expected_bits)

-> check_values
  i = 0
  while i < CASE_COUNT
    value = float_case(i)
    if !float_value?(value)
      fail_check("factory", i, "type", value, "Float")

    floor_expected = ref_floor(value)
    ceil_expected = ref_ceil(value)
    round_expected = ref_round(value)
    sqrt_expected = ref_sqrt(value)
    sq_expected = ref_sq(value)

    check_integer_result("floor", i, "plain", value.floor, floor_expected)
    check_integer_result("floor", i, "one surplus arg", value.floor(17), floor_expected)
    check_integer_result("floor", i, "three surplus args", value.floor(1, 2, 3), floor_expected)

    check_integer_result("ceil", i, "plain", value.ceil, ceil_expected)
    check_integer_result("ceil", i, "one surplus arg", value.ceil(17), ceil_expected)
    check_integer_result("ceil", i, "three surplus args", value.ceil(1, 2, 3), ceil_expected)

    check_integer_result("round", i, "plain", value.round, round_expected)
    check_integer_result("round", i, "one surplus arg", value.round(17), round_expected)
    check_integer_result("round", i, "three surplus args", value.round(1, 2, 3), round_expected)

    check_float_result("sqrt", i, "plain", value.sqrt, sqrt_expected)
    check_float_result("sqrt", i, "one surplus arg", value.sqrt(17), sqrt_expected)
    check_float_result("sqrt", i, "three surplus args", value.sqrt(1, 2, 3), sqrt_expected)

    check_float_result("sq", i, "plain", value.sq, sq_expected)
    check_float_result("sq", i, "one surplus arg", value.sq(17), sq_expected)
    check_float_result("sq", i, "three surplus args", value.sq(1, 2, 3), sq_expected)
    i += 1

-> count_rounding_blocks
  counts = [0, 0, 0]
  value = float_case(12) # +1.5: floor=1, ceil=2, round=2.
  value.floor -> (ignored)
    counts[0] += 1
  value.ceil -> (ignored)
    counts[1] += 1
  value.round -> (ignored)
    counts[2] += 1
  if counts[0] != 1 || counts[1] != 2 || counts[2] != 2
    fail_check("rounding block", 12, "implicit result each", counts, [1, 2, 2])

-> check
  check_values()
  count_rounding_blocks()
  << "PASS Float remaining leaves: 32 encodings, surplus args, and bounded rounding blocks"

-> corpus(kind)
  indexes = nil
  if kind == "floor"
    indexes = [8, 9, 10, 11, 12, 13, 14, 15,
               16, 17, 18, 20, 8, 13, 16, 17]
  elsif kind == "ceil"
    indexes = [8, 9, 10, 11, 12, 13, 14, 15,
               16, 17, 6, 20, 9, 12, 16, 17]
  elsif kind == "round"
    indexes = [10, 11, 12, 13, 14, 15, 8, 9,
               10, 12, 14, 11, 13, 15, 16, 17]
  elsif kind == "sqrt"
    indexes = [0, 1, 2, 4, 6, 8, 10, 12,
               14, 16, 18, 24, 26, 28, 30, 31]
  elsif kind == "sq"
    indexes = [0, 1, 2, 3, 8, 9, 12, 13,
               16, 17, 18, 20, 24, 25, 28, 30]
  else
    << "unknown Float stratum: [kind]"
    exit(2)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_case(indexes[i]))
    i += 1
  values

-> time_floor(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_float_remaining_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].floor) & 0xFFFF
    i += 1
  [ccall("w_float_remaining_thread_cpu_ns") - start_ns, checksum]

-> time_ceil(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_float_remaining_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].ceil) & 0xFFFF
    i += 1
  [ccall("w_float_remaining_thread_cpu_ns") - start_ns, checksum]

-> time_round(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_float_remaining_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].round) & 0xFFFF
    i += 1
  [ccall("w_float_remaining_thread_cpu_ns") - start_ns, checksum]

-> time_sqrt(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_float_remaining_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].sqrt) & 0xFFFF
    i += 1
  [ccall("w_float_remaining_thread_cpu_ns") - start_ns, checksum]

-> time_sq(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_float_remaining_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].sq) & 0xFFFF
    i += 1
  [ccall("w_float_remaining_thread_cpu_ns") - start_ns, checksum]

-> run_once(kind, values, iters, run_id)
  if kind == "floor"
    time_floor(values, iters, run_id)
  elsif kind == "ceil"
    time_ceil(values, iters, run_id)
  elsif kind == "round"
    time_round(values, iters, run_id)
  elsif kind == "sqrt"
    time_sqrt(values, iters, run_id)
  else
    time_sq(values, iters, run_id)

-> fatal_sqrt_block
  value = float_case(14)
  value.sqrt -> (ignored)
    nil
  << "FAIL Float#sqrt trailing block unexpectedly returned"
  exit(9)

-> fatal_sq_block
  value = float_case(14)
  value.sq -> (ignored)
    nil
  << "FAIL Float#sq trailing block unexpectedly returned"
  exit(9)

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  check()
  exit(0)
if mode == "fatal-sqrt-block"
  fatal_sqrt_block()
  exit(9)
if mode == "fatal-sq-block"
  fatal_sq_block()
  exit(9)
if mode != "bench" || args.size() < 3
  << "usage: float-remaining-public bench (floor|ceil|round|sqrt|sq) ITERS [WARMUP]"
  exit(2)

kind = args[1]
iters = args[2].to_i
warmup = args.size() > 3 ? args[3].to_i : DEFAULT_WARMUP
values = corpus(kind)
run_once(kind, values, warmup, 0)
result = run_once(kind, values, iters, 1)
<< "RESULT|[kind]|[result[0]]|[result[1]]"
