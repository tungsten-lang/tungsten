# Exact source-level A/B benchmark for Float#abs.  The production IC shadows a
# same-named core method, so both benchmark legs use unique source names.  The
# C leg calls an unchanged copy of w_ic_float_abs's value operation; the W leg
# works directly on Tungsten's biased-double WValue representation.

use ../../core/float

CASE_COUNT = 22
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000
MIN_LEG_SECONDS = 0.2

+ Float
  -> __c_abs
    ccall("w_ref_float_abs", self)

  -> __w_abs
    # Float WValues store IEEE bits plus 2^48.  Undo that bias before
    # clearing the IEEE sign bit, then restore it.  A magnitude greater than
    # +infinity is NaN; canonicalize it exactly as w_box_double does.  The
    # branch matters for raw positive-NaN payloads made via wvalue_from_bits.
    raw = $value ## i64
    bias = 0x0001000000000000 ## i64
    magnitude = ((raw - bias) & (0x7FFFFFFFFFFFFFFF ## i64)) ## i64
    if magnitude > (0x7FF0000000000000 ## i64)
      return wvalue_from_bits(0x7FF9000000000000 ## i64)
    wvalue_from_bits((magnitude + bias) ## i64)

-> float_case(index)
  ccall("w_ref_float_abs_case", index)

-> float_expected(index)
  ccall("w_ref_float_abs_expected", index)

-> fail_check(path, case_index, got, expected)
  << "FAIL [path] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_bits(path, case_index, got, expected)
  got_bits = wvalue_bits(got)
  expected_bits = wvalue_bits(expected)
  if got_bits != expected_bits
    fail_check(path, case_index, got_bits, expected_bits)

-> run_correctness
  i = 0
  while i < CASE_COUNT
    value = float_case(i)
    expected = float_expected(i)
    c_result = value.__c_abs
    w_result = value.__w_abs
    public_result = value.abs
    check_bits("C/expected", i, c_result, expected)
    check_bits("W/expected", i, w_result, expected)
    check_bits("public/expected", i, public_result, expected)
    check_bits("C/W", i, c_result, w_result)
    i += 1
  << "correctness: ok ([CASE_COUNT * 4] exact-bit checks; signed zero, subnormal, finite, infinity, canonical NaN, and raw NaN payloads)"

-> build_bench_corpus(stratum)
  if stratum == "finite"
    indexes = [6, 7, 8, 9, 10, 11, 20, 21,
               7, 6, 9, 8, 11, 10, 21, 20]
  elsif stratum == "edge"
    indexes = [0, 1, 2, 3, 4, 5, 16, 17,
               1, 0, 3, 2, 5, 4, 17, 16]
  elsif stratum == "nan"
    # Cases 12-15 arrive canonicalized by w_box_double; 18-19 retain raw
    # positive qNaN/sNaN payloads so both sides take their canonical path.
    indexes = [12, 13, 14, 15, 18, 19, 12, 18,
               13, 19, 14, 18, 15, 19, 12, 19]
  else
    << "unknown stratum: [stratum]"
    exit(2)

  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_case(indexes[i]))
    i += 1
  values

-> finish_timing(start_time, checksum)
  [clock() - start_time, checksum]

-> time_abs_c(values, iters)
  checksum = 0
  i = 0
  start_time = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__c_abs
    checksum += (wvalue_bits(result) >> 32) & 0xFFFF
    i += 1
  finish_timing(start_time, checksum)

-> time_abs_w(values, iters)
  checksum = 0
  i = 0
  start_time = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__w_abs
    checksum += (wvalue_bits(result) >> 32) & 0xFFFF
    i += 1
  finish_timing(start_time, checksum)

-> run_single_pair(values, iters, parity)
  if parity == 0
    c_result = time_abs_c(values, iters)
    w_result = time_abs_w(values, iters)
  else
    w_result = time_abs_w(values, iters)
    c_result = time_abs_c(values, iters)
  [c_result, w_result]

-> combine_timing(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(stratum, values, iters, parity, emit = true)
  # parity 0 gives C/W/W/C; parity 1 gives W/C/C/W.  Summing the two legs
  # cancels first-order frequency and thermal drift within each process.
  first = run_single_pair(values, iters, parity)
  second = run_single_pair(values, iters, parity == 0 ? 1 : 0)
  if emit && (first[0][0] < MIN_LEG_SECONDS || first[1][0] < MIN_LEG_SECONDS || second[0][0] < MIN_LEG_SECONDS || second[1][0] < MIN_LEG_SECONDS)
    << "FAIL timing leg shorter than [MIN_LEG_SECONDS]s; increase ITERS"
    exit(2)
  c_result = combine_timing(first[0], second[0])
  w_result = combine_timing(first[1], second[1])
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum abs/[stratum]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  if emit
    c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
    w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
    << "RESULT|[stratum]|[c_ns]|[w_ns]|[w_result[0] / c_result[0]]|[c_result[1]]"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"

if mode == "check"
  run_correctness()
  exit(0)

iters = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = args.size() > 2 ? args[2].to_i : 0
if parity != 0 && parity != 1
  << "sample parity must be 0 or 1"
  exit(2)

stratum = args.size() > 3 ? args[3] : "finite"
values = build_bench_corpus(stratum)
run_pair(stratum, values, WARMUP_ITERS, parity, false)
run_pair(stratum, values, iters, parity)
