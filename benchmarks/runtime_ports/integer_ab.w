# Function-level A/B benchmark for Integer/Number leaf methods moved from C
# IC handlers into native Tungsten class bodies. Correctness includes both i48
# boundaries and operations whose result crosses into BigInt.

use ../../core/integer

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 2_000_000
WARMUP_ITERS = 20_000

+ Integer
  -> __c_prev
    ccall("w_ref_integer_prev", self)

  -> __c_succ
    ccall("w_ref_integer_succ", self)

  -> __c_next
    ccall("w_ref_integer_succ", self)

  -> __c_zero?
    ccall("w_ref_integer_zero_p", self)

  -> __c_even?
    ccall("w_ref_integer_even_p", self)

  -> __c_odd?
    ccall("w_ref_integer_odd_p", self)

  -> __c_negative?
    ccall("w_ref_integer_negative_p", self)

  -> __c_positive?
    ccall("w_ref_integer_positive_p", self)

  -> __c_sq
    ccall("w_ref_integer_sq", self)

-> build_corpus
  [-140_737_488_355_328, -140_737_488_355_327,
   -11_863_285, -11_863_284, -3, -2, -1, 0,
   1, 2, 3, 11_863_283, 11_863_284,
   140_737_488_355_326, 140_737_488_355_327, 42]

-> check_value(name, case_index, got, expected)
  if got != expected
    << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
    exit(1)

-> run_correctness(values)
  i = 0
  while i < values.size()
    value = values[i]
    check_value("prev", i, value.prev, value.__c_prev)
    check_value("succ", i, value.succ, value.__c_succ)
    check_value("next", i, value.next, value.__c_next)
    check_value("zero?", i, value.zero?, value.__c_zero?)
    check_value("even?", i, value.even?, value.__c_even?)
    check_value("odd?", i, value.odd?, value.__c_odd?)
    check_value("negative?", i, value.negative?, value.__c_negative?)
    check_value("positive?", i, value.positive?, value.__c_positive?)
    check_value("sq", i, value.sq, value.__c_sq)
    i += 1
  << "correctness: ok ([values.size() * 9] exact C/W comparisons; i48 and BigInt crossover)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_prev_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_prev & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_prev_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].prev & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_succ_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_succ & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_succ_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].succ & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_next_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_next & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_next_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].next & 0xFF
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
    checksum += values[i & CORPUS_MASK].zero? ? 1 : 0
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
    checksum += values[i & CORPUS_MASK].even? ? 1 : 0
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
    checksum += values[i & CORPUS_MASK].odd? ? 1 : 0
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
    checksum += values[i & CORPUS_MASK].negative? ? 1 : 0
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
    checksum += values[i & CORPUS_MASK].positive? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_sq_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_sq & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_sq_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].sq & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> report_result(name, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum [name]: C=[c_result[1]] W=[w_result[1]]"
    exit(1)
  c_ns = c_result[0] * 1_000_000_000 / iters
  w_ns = w_result[0] * 1_000_000_000 / iters
  ratio = w_result[0] / c_result[0]
  << "RESULT|[name]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_pair(values, iters, parity, name, emit = true)
  if name == "prev"
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
  else
    if parity == 0
      c_result = time_sq_c(values, iters)
      w_result = time_sq_w(values, iters)
    else
      w_result = time_sq_w(values, iters)
      c_result = time_sq_c(values, iters)
  if emit
    report_result(name, c_result, w_result, iters)

-> run_bench(values, iters, parity)
  names = ["prev", "succ", "next", "zero?", "even?", "odd?",
           "negative?", "positive?", "sq"]
  i = 0
  while i < names.size()
    run_pair(values, WARMUP_ITERS, parity, names[i], false)
    i += 1
  i = 0
  while i < names.size()
    run_pair(values, iters, parity, names[i])
    i += 1

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
values = build_corpus()

if mode == "check"
  run_correctness(values)
  exit(0)

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
