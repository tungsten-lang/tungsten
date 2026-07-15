# Strict A/B batch for cheap BigInt runtime IC handlers. Every benchmark name
# is unique, so the public BigInt IC table cannot shadow either source leg.

CORRECTNESS_CASES = 26
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 1_000_000

# Standalone superclass anchor. The project autoload reopens BigInt from its
# core declaration (`BigInt < Int`); this local anchor keeps that registration
# linkable without importing the unfinished Real/Number scaffold hierarchy.
+ Int

+ BigInt
  # Benchmark-local mirror of WBigint. Keeping this declaration here avoids
  # pulling the unfinished abstract numeric hierarchy into a standalone port
  # benchmark while exercising the same corrected offsets and raw loads.
  - data
    u8[3] _pad
    i32 length
    u32 capacity
    u32 _pad2
    u64[] limbs

  -> __c_to_i
    ccall("w_ref_bigint_to_i", self)

  -> __c_prev
    ccall("w_ref_bigint_prev", self)

  -> __c_succ
    ccall("w_ref_bigint_succ", self)

  -> __c_next
    ccall("w_ref_bigint_succ", self)

  -> __c_zero?
    ccall("w_ref_bigint_zero_p", self)

  -> __c_even?
    ccall("w_ref_bigint_even_p", self)

  -> __c_odd?
    ccall("w_ref_bigint_odd_p", self)

  -> __c_negative?
    ccall("w_ref_bigint_negative_p", self)

  -> __c_positive?
    ccall("w_ref_bigint_positive_p", self)

  -> __w_to_i
    self

  -> __w_prev
    self - 1

  -> __w_succ
    self + 1

  -> __w_next
    self + 1

  # Cross-mode-safe source baselines. These deliberately use public numeric
  # operators so they behave identically in compiled and tree-walk execution.
  -> __w_zero?
    self == 0

  -> __w_even?
    self % 2 == 0

  -> __w_odd?
    self % 2 != 0

  -> __w_negative?
    self < 0

  -> __w_positive?
    self > 0

  # Compiled-only direct controls. Keep them separately addressable until the
  # interpreter gains a BigInt field bridge; they must not be production ports.
  -> __w_direct_zero?
    n = $length ## i64
    n == 0

  -> __w_direct_even?
    n = $length ## i64
    if n == 0
      return true
    # `limbs` is a flexible inline C array. A bare field load reads limb 0;
    # wvalue_bits keeps that machine word raw instead of treating it as WValue.
    low = wvalue_bits($limbs) ## i64
    (low & 1) == 0

  -> __w_direct_odd?
    n = $length ## i64
    if n == 0
      return false
    low = wvalue_bits($limbs) ## i64
    (low & 1) != 0

  -> __w_direct_negative?
    n = $length ## i64
    n < 0

  -> __w_direct_positive?
    n = $length ## i64
    n > 0

-> bigint_case(index)
  ccall("w_ref_bigint_leaf_case", index)

-> is_bigint(value)
  ccall("w_ref_bigint_value_p", value)

-> consume_low_byte(value)
  ccall("w_ref_bigint_consume_low_byte", value)

-> fail_check(path, case_index, got, expected)
  << "FAIL [path] case=[case_index] got=[got] expected=[expected]"
  exit(1)

-> check_value(path, case_index, got, expected)
  if got != expected
    fail_check(path, case_index, got, expected)

-> run_correctness
  expected_zero = [true, false, false, false, false, false, false, false,
                   false, false, false, false, false, false, false, false,
                   false, false, false, false, false, false, false, false,
                   false, false]
  expected_negative = [false, false, false, true, true, false, false, true,
                       false, true, false, false, true, true, false, true,
                       false, true, false, true, false, true, false, true,
                       false, true]
  expected_odd = [false, false, true, true, false, true, false, false,
                  true, true, false, true, false, true, true, true,
                  false, false, false, false, true, true, false, false,
                  true, true]

  i = 0
  while i < CORRECTNESS_CASES
    value = bigint_case(i)
    zero = expected_zero[i]
    negative = expected_negative[i]
    odd = expected_odd[i]
    positive = !zero && !negative
    even = !odd

    check_value("C zero?", i, value.__c_zero?, zero)
    check_value("W zero?", i, value.__w_zero?, zero)
    check_value("W-direct zero?", i, value.__w_direct_zero?, zero)
    check_value("C even?", i, value.__c_even?, even)
    check_value("W even?", i, value.__w_even?, even)
    check_value("W-direct even?", i, value.__w_direct_even?, even)
    check_value("C odd?", i, value.__c_odd?, odd)
    check_value("W odd?", i, value.__w_odd?, odd)
    check_value("W-direct odd?", i, value.__w_direct_odd?, odd)
    check_value("C negative?", i, value.__c_negative?, negative)
    check_value("W negative?", i, value.__w_negative?, negative)
    check_value("W-direct negative?", i, value.__w_direct_negative?, negative)
    check_value("C positive?", i, value.__c_positive?, positive)
    check_value("W positive?", i, value.__w_positive?, positive)
    check_value("W-direct positive?", i, value.__w_direct_positive?, positive)

    original_bits = wvalue_bits(value)
    c_to_i = value.__c_to_i
    w_to_i = value.__w_to_i
    check_value("to_i C/W", i, c_to_i, w_to_i)
    check_value("to_i C identity", i, wvalue_bits(c_to_i), original_bits)
    check_value("to_i W identity", i, wvalue_bits(w_to_i), original_bits)

    c_prev = value.__c_prev
    w_prev = value.__w_prev
    c_succ = value.__c_succ
    w_succ = value.__w_succ
    c_next = value.__c_next
    w_next = value.__w_next
    check_value("prev C/W", i, c_prev, w_prev)
    check_value("succ C/W", i, c_succ, w_succ)
    check_value("next C/W", i, c_next, w_next)
    check_value("C next/succ", i, c_next, c_succ)
    check_value("W next/succ", i, w_next, w_succ)
    check_value("C prev inverse", i, c_prev + 1, value)
    check_value("W prev inverse", i, w_prev + 1, value)
    check_value("C succ inverse", i, c_succ - 1, value)
    check_value("W succ inverse", i, w_succ - 1, value)

    # Exact current normalization edges: zero +/- 1 are inline and +2^47.prev
    # demotes. The runtime currently leaves -(2^47+1).succ as BigInt because
    # bigint_normalize gates one-limb demotion on magnitude <= I48_MAX, even
    # though -2^47 itself has an inline representation.
    prev_big = i != 0 && i != 1
    succ_big = i != 0
    check_value("C prev representation", i, is_bigint(c_prev), prev_big)
    check_value("W prev representation", i, is_bigint(w_prev), prev_big)
    check_value("C succ representation", i, is_bigint(c_succ), succ_big)
    check_value("W succ representation", i, is_bigint(w_succ), succ_big)
    check_value("C next representation", i, is_bigint(c_next), succ_big)
    check_value("W next representation", i, is_bigint(w_next), succ_big)
    i += 1

  << "correctness: ok ([CORRECTNESS_CASES * 33] checks; generic/direct predicates, i48 crossover, and 1-4 limbs)"

-> build_bench_corpus
  indexes = [0, 1, 2, 3, 4, 5, 6, 7,
             8, 9, 10, 11, 16, 17, 24, 25]
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(bigint_case(indexes[i]))
    i += 1
  values

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_to_i_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].__c_to_i) & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_to_i_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += wvalue_bits(values[i & CORPUS_MASK].__w_to_i) & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_prev_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__c_prev)
    i += 1
  finish_timing(start_ns, checksum)

-> time_prev_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__w_prev)
    i += 1
  finish_timing(start_ns, checksum)

-> time_succ_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__c_succ)
    i += 1
  finish_timing(start_ns, checksum)

-> time_succ_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__w_succ)
    i += 1
  finish_timing(start_ns, checksum)

-> time_next_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__c_next)
    i += 1
  finish_timing(start_ns, checksum)

-> time_next_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += consume_low_byte(values[i & CORPUS_MASK].__w_next)
    i += 1
  finish_timing(start_ns, checksum)

-> time_zero_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_zero? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_zero_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_zero? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_even_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_even? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_even_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_even? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_odd_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_odd? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_odd_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_odd? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_negative_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_negative? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_negative_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_negative? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_positive_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_positive? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_positive_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_positive? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_direct_zero_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_direct_zero? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_direct_even_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_direct_even? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_direct_odd_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_direct_odd? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_direct_negative_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_direct_negative? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_direct_positive_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_direct_positive? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum [name]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
  w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_single_pair(values, iters, parity, name)
  if name == "to_i"
    if parity == 0
      c_result = time_to_i_c(values, iters)
      w_result = time_to_i_w(values, iters)
    else
      w_result = time_to_i_w(values, iters)
      c_result = time_to_i_c(values, iters)
  elsif name == "prev"
    if parity == 0
      c_result = time_prev_c(values, iters)
      w_result = time_prev_w(values, iters)
    else
      w_result = time_prev_w(values, iters)
      c_result = time_prev_c(values, iters)
  elsif name == "succ"
    if parity == 0
      c_result = time_succ_c(values, iters)
      w_result = time_succ_w(values, iters)
    else
      w_result = time_succ_w(values, iters)
      c_result = time_succ_c(values, iters)
  elsif name == "next"
    if parity == 0
      c_result = time_next_c(values, iters)
      w_result = time_next_w(values, iters)
    else
      w_result = time_next_w(values, iters)
      c_result = time_next_c(values, iters)
  elsif name == "zero?"
    if parity == 0
      c_result = time_zero_c(values, iters)
      w_result = time_zero_w(values, iters)
    else
      w_result = time_zero_w(values, iters)
      c_result = time_zero_c(values, iters)
  elsif name == "even?"
    if parity == 0
      c_result = time_even_c(values, iters)
      w_result = time_even_w(values, iters)
    else
      w_result = time_even_w(values, iters)
      c_result = time_even_c(values, iters)
  elsif name == "odd?"
    if parity == 0
      c_result = time_odd_c(values, iters)
      w_result = time_odd_w(values, iters)
    else
      w_result = time_odd_w(values, iters)
      c_result = time_odd_c(values, iters)
  elsif name == "negative?"
    if parity == 0
      c_result = time_negative_c(values, iters)
      w_result = time_negative_w(values, iters)
    else
      w_result = time_negative_w(values, iters)
      c_result = time_negative_c(values, iters)
  elsif name == "positive?"
    if parity == 0
      c_result = time_positive_c(values, iters)
      w_result = time_positive_w(values, iters)
    else
      w_result = time_positive_w(values, iters)
      c_result = time_positive_c(values, iters)
  elsif name == "direct-zero?"
    if parity == 0
      c_result = time_zero_c(values, iters)
      w_result = time_direct_zero_w(values, iters)
    else
      w_result = time_direct_zero_w(values, iters)
      c_result = time_zero_c(values, iters)
  elsif name == "direct-even?"
    if parity == 0
      c_result = time_even_c(values, iters)
      w_result = time_direct_even_w(values, iters)
    else
      w_result = time_direct_even_w(values, iters)
      c_result = time_even_c(values, iters)
  elsif name == "direct-odd?"
    if parity == 0
      c_result = time_odd_c(values, iters)
      w_result = time_direct_odd_w(values, iters)
    else
      w_result = time_direct_odd_w(values, iters)
      c_result = time_odd_c(values, iters)
  elsif name == "direct-negative?"
    if parity == 0
      c_result = time_negative_c(values, iters)
      w_result = time_direct_negative_w(values, iters)
    else
      w_result = time_direct_negative_w(values, iters)
      c_result = time_negative_c(values, iters)
  elsif name == "direct-positive?"
    if parity == 0
      c_result = time_positive_c(values, iters)
      w_result = time_direct_positive_w(values, iters)
    else
      w_result = time_direct_positive_w(values, iters)
      c_result = time_positive_c(values, iters)
  else
    << "unknown benchmark function: [name]"
    exit(2)
  [c_result, w_result]

-> combine_timing(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(values, iters, parity, name, emit = true)
  # ABBA/BAAB inside one process cancels first-order clock/frequency drift.
  first = run_single_pair(values, iters, parity, name)
  second = run_single_pair(values, iters, parity == 0 ? 1 : 0, name)
  c_result = combine_timing(first[0], second[0])
  w_result = combine_timing(first[1], second[1])
  if emit
    report_result(name, c_result, w_result, iters)

-> run_bench(values, iters, parity, name)
  run_pair(values, WARMUP_ITERS, parity, name, false)
  run_pair(values, iters, parity, name)

args = argv()
mode = args.size() > 0 ? args[0] : "check"

if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench"
  << "mode must be check or bench"
  exit(2)

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

name = args.size() > 3 ? args[3] : "zero?"
run_bench(build_bench_corpus(), iters, parity, name)
