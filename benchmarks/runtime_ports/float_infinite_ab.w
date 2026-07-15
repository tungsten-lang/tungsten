# Function-level A/B benchmark for native Float#infinite?. The timed source
# path uses a unique method because the production C IC shadows a same-named
# core body until that IC is removed for a separate public-dispatch trial.

use ../../core/float

CORRECTNESS_CASES = 18
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 100_000

+ Float
  # Exact current C classification, copied into float_infinite_ref.c.
  -> __c_infinite?
    ccall("w_ref_float_infinite_p", self)

  # WValue stores Float as IEEE bits plus W_DOUBLE_BIAS. These are the exact
  # biased words for +infinity and -infinity (the latter written as signed i64).
  -> __w_infinite?
    bits = $value ## i64
    bits == 0x7FF1000000000000 || bits == -4222124650659840

-> float_case(index)
  ccall("w_ref_float_infinite_case", index)

-> fail_check(path, case_index, got, expected)
  << "FAIL [path] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(path, case_index, got, expected)
  if got != expected
    fail_check(path, case_index, got, expected)

-> run_correctness
  # +0, -0, two signs of least/greatest subnormal, least normal, 1, greatest
  # finite, quiet/signaling NaNs, then the two infinities. w_box_double
  # canonicalizes all NaNs just as normal runtime construction does.
  expected = [false, false, false, false, false, false,
              false, false, false, false, false, false,
              false, false, false, false, true, true]
  i = 0
  while i < CORRECTNESS_CASES
    value = float_case(i)
    c_result = value.__c_infinite?
    w_result = value.__w_infinite?
    public_result = value.infinite?
    check_value("C", i, c_result, expected[i])
    check_value("W", i, w_result, expected[i])
    check_value("public", i, public_result, expected[i])
    check_value("C/W", i, w_result, c_result)
    i += 1
  << "correctness: ok ([CORRECTNESS_CASES * 4] checks; finite, +/-0, subnormal, normal, NaN, and +/-infinity)"

-> build_bench_corpus
  # Balanced true/false results keep both outcomes live. Every IEEE category
  # is already checked above; corpus construction is outside timed intervals.
  indexes = [0, 16, 1, 17, 2, 16, 3, 17,
             6, 16, 7, 17, 12, 16, 14, 17]
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_case(indexes[i]))
    i += 1
  values

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_infinite_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_infinite? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_infinite_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_infinite? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum infinite?: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|infinite?|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(values, iters, parity, emit = true)
  if parity == 0
    c_result = time_infinite_c(values, iters)
    w_result = time_infinite_w(values, iters)
  else
    w_result = time_infinite_w(values, iters)
    c_result = time_infinite_c(values, iters)
  if emit
    report_result(c_result, w_result, iters)

-> run_bench(values, iters, parity)
  run_pair(values, WARMUP_ITERS, parity, false)
  run_pair(values, iters, parity)

args = argv()
mode = args.size() > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
  exit(0)

values = build_bench_corpus()
iters = DEFAULT_ITERS
if args.size() > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = 0
if args.size() > 2
  if args[2] != "0" && args[2] != "1"
    << "sample parity must be 0 (C/W) or 1 (W/C)"
    exit(2)
  parity = args[2].to_i

run_bench(values, iters, parity)
