# True-public before/after benchmark for the C-to-source BigInt#neg!/abs!
# port. The noinline C observer is identical in both builds and keeps each
# field mutation visible to the optimizer.

CASE_COUNT = 16
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 20_000_000

-> fixture(index)
  ccall("w_bigbang_fixture", index)

-> signed_size(value)
  ccall("w_bigbang_signed_size", value)

-> set_size(value, size)
  ccall("w_bigbang_set_size", value, size)

-> observe(value)
  ccall("w_bigbang_observe", value)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> run_correctness
  check_value("fixture count", ccall("w_bigbang_case_count"), CASE_COUNT)
  i = 0
  while i < CASE_COUNT
    value = fixture(i)
    original_size = ccall("w_bigbang_expected_size", i)
    original_bits = wvalue_bits(value)

    negated = value.neg!
    check_value("neg return [i]", wvalue_bits(negated), original_bits)
    check_value("neg size [i]", signed_size(value), 0 - original_size)

    restored = value.neg!
    check_value("neg involution return [i]", wvalue_bits(restored), original_bits)
    check_value("neg involution size [i]", signed_size(value), original_size)

    set_size(value, 0 - original_size.abs)
    absolute = value.abs!
    check_value("abs negative return [i]", wvalue_bits(absolute), original_bits)
    check_value("abs negative size [i]", signed_size(value), original_size.abs)

    absolute_again = value.abs!
    check_value("abs positive return [i]", wvalue_bits(absolute_again), original_bits)
    check_value("abs positive size [i]", signed_size(value), original_size.abs)
    i += 1
  << "correctness: ok ([CASE_COUNT * 8] identity/sign checks; 1-4 limbs and spare capacity)"

-> build_corpus
  values = []
  i = 0
  while i < CORPUS_SIZE
    value = fixture(i)
    set_size(value, signed_size(value).abs)
    values.push(value)
    i += 1
  values

-> time_neg(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.neg!
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_abs_positive(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.abs!
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> time_neg_abs_pair(values, iters, run_id)
  checksum = 0
  i = 0
  started = ccall("w_bigbang_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    value.neg!
    value.abs!
    checksum += observe(value)
    i += 1
  [ccall("w_bigbang_thread_cpu_ns") - started, checksum]

-> run_bench(name, iters)
  values = build_corpus()
  if name == "neg"
    result = time_neg(values, iters, 1)
    calls = iters
  elsif name == "abs-positive"
    result = time_abs_positive(values, iters, 1)
    calls = iters
  elsif name == "neg-abs-pair"
    result = time_neg_abs_pair(values, iters, 1)
    calls = iters * 2
  else
    << "unknown benchmark: [name]"
    exit(2)
  << "RESULT|[name]|[result[0]]|[calls]|[result[1]]"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
if mode == "check"
  run_correctness()
  exit(0)

name = args.size() > 1 ? args[1] : "neg"
iters = args.size() > 2 ? args[2].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)
run_bench(name, iters)
