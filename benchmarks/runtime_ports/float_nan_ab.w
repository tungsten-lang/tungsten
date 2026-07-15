# Function-level A/B benchmark for replacing Float#nan?'s C isnan handler
# with the canonical biased-NaN word comparison used by Tungsten's WValue ABI.
# The unique source body remains benchmarkable after the balanced public trial
# failed its retention gate.

use ../../core/float

CASE_COUNT = 18
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ Float
  -> __c_nan?
    ccall("w_ref_float_nan_p", self)

  -> __w_nan?
    ($value ## i64) == 0x7FF9000000000000

-> float_case(index)
  ccall("w_ref_float_nan_case", index)

-> run_correctness
  expected = [false, false, false, false, false, false,
              false, false, false, false, false, false,
              true, true, true, true, false, false]
  i = 0
  while i < CASE_COUNT
    value = float_case(i)
    c_result = value.__c_nan?
    w_result = value.__w_nan?
    if c_result != expected[i] || w_result != c_result || value.nan? != c_result
      << "FAIL nan? case=[i] C=[c_result] W=[w_result] public=[value.nan?] expected=[expected[i]]"
      exit(1)
    i += 1
  << "correctness: ok ([CASE_COUNT * 3] checks; finite, NaN payloads/signs, and infinities)"

-> build_corpus
  indexes = [0, 12, 1, 13, 2, 14, 3, 15,
             6, 12, 7, 13, 10, 14, 16, 15]
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_case(indexes[i]))
    i += 1
  values

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_nan_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_nan? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_nan_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_nan? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> run_single_pair(values, iters, parity)
  if parity == 0
    c_result = time_nan_c(values, iters)
    w_result = time_nan_w(values, iters)
  else
    w_result = time_nan_w(values, iters)
    c_result = time_nan_c(values, iters)
  [c_result, w_result]

-> combine_timing(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(values, iters, parity, emit = true)
  # One process runs C/W/W/C or W/C/C/W. Summing the two measurements for
  # each implementation cancels first-order frequency and thermal drift.
  first = run_single_pair(values, iters, parity)
  second = run_single_pair(values, iters, parity == 0 ? 1 : 0)
  c_result = combine_timing(first[0], second[0])
  w_result = combine_timing(first[1], second[1])
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum nan?: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  if emit
    c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
    w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
    << "RESULT|nan?|[c_ns]|[w_ns]|[w_result[0] / c_result[0]]|[c_result[1]]"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
values = build_corpus()
if mode == "check"
  run_correctness()
  exit(0)
iters = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS
parity = args.size() > 2 ? args[2].to_i : 0
run_pair(values, WARMUP_ITERS, parity, false)
run_pair(values, iters, parity)
