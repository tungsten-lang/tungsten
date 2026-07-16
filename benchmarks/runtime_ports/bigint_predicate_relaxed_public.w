# True public-dispatch driver for BigInt#zero?/#even?/#odd?/#negative?/
# #positive?. It deliberately has no `use` directive: the baseline reaches the
# native IC table, while the candidate must schedule BigInt from the predicate
# spelling and register its source class for the same C-produced receivers.

CASE_COUNT = 32
CORPUS_MASK = 15
DEFAULT_ITERS = 10_000_000
DEFAULT_WARMUP = 250_000

-> fixture(index)
  ccall("w_bigpred_fixture", index)

-> reference_mask(value)
  ccall("w_bigpred_reference_mask", value)

-> fixture_matches?(value, index)
  ccall("w_bigpred_fixture_matches", value, index)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> mask_bit(mask, bit)
  (mask & bit) != 0

-> check_bool(name, got, expected)
  check_value(name, got, expected)
  check_value("[name].bits", wvalue_bits(got), wvalue_bits(expected))

-> check_case(index)
  value = fixture(index)
  check_value("case.[index].factory", fixture_matches?(value, index), true)
  mask = reference_mask(value)

  check_bool("case.[index].zero", value.zero?, mask_bit(mask, 1))
  check_bool("case.[index].even", value.even?, mask_bit(mask, 2))
  check_bool("case.[index].odd", value.odd?, mask_bit(mask, 4))
  check_bool("case.[index].negative", value.negative?, mask_bit(mask, 8))
  check_bool("case.[index].positive", value.positive?, mask_bit(mask, 16))

  # The old arity -1 IC wrappers ignored every supplied positional argument.
  # Source lookup intentionally keeps the runtime's name-only fallback.
  check_bool("case.[index].zero.extra1", value.zero?(101), mask_bit(mask, 1))
  check_bool("case.[index].zero.extra4", value.zero?(1, 2, 3, 4), mask_bit(mask, 1))
  check_bool("case.[index].even.extra1", value.even?(101), mask_bit(mask, 2))
  check_bool("case.[index].even.extra4", value.even?(1, 2, 3, 4), mask_bit(mask, 2))
  check_bool("case.[index].odd.extra1", value.odd?(101), mask_bit(mask, 4))
  check_bool("case.[index].odd.extra4", value.odd?(1, 2, 3, 4), mask_bit(mask, 4))
  check_bool("case.[index].negative.extra1", value.negative?(101), mask_bit(mask, 8))
  check_bool("case.[index].negative.extra4", value.negative?(1, 2, 3, 4), mask_bit(mask, 8))
  check_bool("case.[index].positive.extra1", value.positive?(101), mask_bit(mask, 16))
  check_bool("case.[index].positive.extra4", value.positive?(1, 2, 3, 4), mask_bit(mask, 16))

  check_value("case.[index].stable", fixture_matches?(value, index), true)

-> run_correctness
  check_value("fixture count", ccall("w_bigpred_case_count"), CASE_COUNT)
  i = 0
  while i < CASE_COUNT
    check_case(i)
    i += 1
  << "correctness: ok (32 layouts; signed size, limb parity, zero/no-storage, spare capacity, noncanonical headers, extras, Bool bits, and receiver stability)"

-> corpus(indexes)
  values = []
  i = 0
  while i < 16
    values.push(fixture(indexes[i]))
    i += 1
  values

-> corpus_for(stratum)
  if stratum.ends_with?("zero_nostorage")
    return corpus([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
  if stratum.ends_with?("zero_spare")
    return corpus([1, 2, 1, 2, 2, 1, 2, 1, 1, 2, 1, 2, 2, 1, 2, 1])
  if stratum in ("negative.zero" "positive.zero")
    return corpus([0, 1, 2, 0, 1, 2, 0, 2, 1, 0, 2, 1, 0, 1, 2, 0])
  if stratum == "zero.one"
    return corpus([3, 4, 5, 6, 7, 8, 9, 10, 23, 24, 27, 28, 3, 6, 23, 28])
  if stratum == "zero.multi"
    return corpus([11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 25, 26, 29, 30])
  if stratum.ends_with?("one_even")
    return corpus([3, 5, 7, 9, 23, 27, 28, 3, 5, 7, 9, 23, 27, 28, 5, 23])
  if stratum.ends_with?("one_odd")
    return corpus([4, 6, 8, 10, 24, 4, 6, 8, 10, 24, 6, 10, 24, 4, 8, 24])
  if stratum.ends_with?("multi_even")
    return corpus([11, 13, 15, 17, 19, 21, 25, 30, 11, 13, 15, 17, 19, 21, 25, 30])
  if stratum.ends_with?("multi_odd")
    return corpus([12, 14, 16, 18, 20, 22, 26, 29, 31, 12, 14, 16, 18, 20, 26, 31])
  if stratum.ends_with?("one_positive")
    return corpus([3, 4, 7, 8, 23, 27, 3, 4, 7, 8, 23, 27, 4, 8, 23, 27])
  if stratum.ends_with?("one_negative")
    return corpus([5, 6, 9, 10, 24, 28, 5, 6, 9, 10, 24, 28, 6, 10, 24, 28])
  if stratum.ends_with?("multi_positive")
    return corpus([11, 12, 15, 16, 19, 20, 25, 29, 31, 11, 12, 16, 20, 25, 29, 31])
  if stratum.ends_with?("multi_negative")
    return corpus([13, 14, 17, 18, 21, 22, 26, 30, 13, 14, 17, 18, 21, 22, 26, 30])
  fail_check("stratum", "unknown [stratum]")

# Each timing body has three parameters and takes its thread-CPU timestamps by
# direct ccall. That keeps the compiler's <=2-argument pure-function memoizer
# from caching a clock wrapper. Predicate results are consumed immediately as
# exact Bool WValue bits; do not assign a heap-Integer-typed intermediate (the
# active identity audit found that such assignments can be mis-nanunboxed).
-> time_zero(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigpred_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].zero?)
    i += 1
  [ccall("w_bigpred_thread_cpu_ns") - started, checksum]

-> time_even(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigpred_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].even?)
    i += 1
  [ccall("w_bigpred_thread_cpu_ns") - started, checksum]

-> time_odd(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigpred_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].odd?)
    i += 1
  [ccall("w_bigpred_thread_cpu_ns") - started, checksum]

-> time_negative(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigpred_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].negative?)
    i += 1
  [ccall("w_bigpred_thread_cpu_ns") - started, checksum]

-> time_positive(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigpred_thread_cpu_ns")
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].positive?)
    i += 1
  [ccall("w_bigpred_thread_cpu_ns") - started, checksum]

-> timed(stratum, values, iters, run_id)
  if stratum.starts_with?("zero.")
    return time_zero(values, iters, run_id)
  if stratum.starts_with?("even.")
    return time_even(values, iters, run_id)
  if stratum.starts_with?("odd.")
    return time_odd(values, iters, run_id)
  if stratum.starts_with?("negative.")
    return time_negative(values, iters, run_id)
  if stratum.starts_with?("positive.")
    return time_positive(values, iters, run_id)
  fail_check("timing", "unknown [stratum]")

-> run_bench(stratum, iters, warmup)
  values = corpus_for(stratum)
  timed(stratum, values, warmup, 0)
  result = timed(stratum, values, iters, 1)
  << "RESULT|[stratum]|[result[0]]|[iters]|[result[1]]"

-> run_block_fatal(method)
  value = fixture(4)
  if method == "zero"
    value.zero? -> 99
  elsif method == "even"
    value.even? -> 99
  elsif method == "odd"
    value.odd? -> 99
  elsif method == "negative"
    value.negative? -> 99
  elsif method == "positive"
    value.positive? -> 99
  else
    fail_check("block", "unknown method [method]")
  fail_check("block", "[method]? unexpectedly returned")

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)
if mode == "block-fatal"
  if args.size() < 2
    fail_check("block", "missing method")
  run_block_fatal(args[1])
  exit(9)
if mode != "bench" || args.size() < 4
  << "usage: bigint-predicate-relaxed-public bench STRATUM ITERS WARMUP"
  exit(2)
run_bench(args[1], args[2].to_i, args[3].to_i)
