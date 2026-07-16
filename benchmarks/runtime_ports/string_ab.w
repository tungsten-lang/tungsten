# Function-level A/B benchmark for a candidate String#empty? move from the C
# IC handler to core/string_native.w. The uniquely named __w_empty? method
# prevents the current public C IC registration from shadowing the source
# candidate. The corpus covers inline, slab, heap, rope-flattened, and Symbol
# representations plus operations that produce empty strings.

use ../../core/string_native

CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ String
  -> __c_empty?
    ccall("w_ref_string_empty_p", self)

  # Optimized candidate. The current core body computes
  # `(($value >> 1) & 7) == 0`; testing the same three storage-mode bits in
  # place removes the shift while preserving every representation case.
  -> __w_empty?
    ($value & 14) == 0

  -> __storage_mode
    ($value >> 1) & 7

-> build_corpus
  heap_long = "h" * 80
  heap_short = "".concat("h")
  rope_left = "l" * 40
  rope_right = "r" * 40
  rope = rope_left + rope_right

  ["", "a", "12345", "123456", "a slab-backed string",
   heap_short, heap_long, rope,
   "abc".slice(99, 3), "abc" * 0, "   ".strip,
   "".upcase, "".downcase, "".capitalize,
   "".to_sym, "x".to_sym]

-> check_value(name, case_index, got, expected)
  if got != expected
    << "FAIL [name] case=[case_index] got=[got] expected=[expected]"
    exit(1)

-> run_correctness(values)
  i = 0
  while i < values.size
    check_value("empty?", i, values[i].__w_empty?, values[i].__c_empty?)
    i += 1

  # Confirm the representation assumptions behind the bit-level body. Rope
  # dispatch flattens before entering String, so its observed mode is heap.
  check_value("inline empty mode", 0, values[0].__storage_mode, 0)
  check_value("inline mode", 1, values[1].__storage_mode, 1)
  check_value("inline max mode", 2, values[2].__storage_mode, 5)
  check_value("slab mode", 3, values[3].__storage_mode, 6)
  check_value("heap short mode", 5, values[5].__storage_mode, 7)
  check_value("heap long mode", 6, values[6].__storage_mode, 7)
  check_value("flattened rope mode", 7, values[7].__storage_mode, 7)
  check_value("empty symbol mode", 14, values[14].__storage_mode, 0)

  << "correctness: ok ([values.size] exact C/W comparisons; inline/slab/heap/rope/symbol)"

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_empty_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> time_empty_w(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_empty? ? 1 : 0
    i += 1
  finish_timing(start_ns, checksum)

-> run_single_pair(values, iters, parity)
  if parity == 0
    c_result = time_empty_c(values, iters)
    w_result = time_empty_w(values, iters)
  else
    w_result = time_empty_w(values, iters)
    c_result = time_empty_c(values, iters)
  [c_result, w_result]

-> combine_timing(first, second)
  [first[0] + second[0], first[1] + second[1]]

-> run_pair(values, iters, parity, emit = true)
  first = run_single_pair(values, iters, parity)
  second = run_single_pair(values, iters, parity == 0 ? 1 : 0)
  c_result = combine_timing(first[0], second[0])
  w_result = combine_timing(first[1], second[1])

  if c_result[1] != w_result[1]
    << "FAIL benchmark checksum empty?: C=[c_result[1]] W=[w_result[1]]"
    exit(1)

  if emit
    c_ns = c_result[0] * 1_000_000_000 / (iters * 2)
    w_ns = w_result[0] * 1_000_000_000 / (iters * 2)
    ratio = w_result[0] / c_result[0]
    << "RESULT|empty?|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

args = argv()
mode = args.size > 0 ? args[0] : "bench"
values = build_corpus()

if mode == "check"
  run_correctness(values)
  exit(0)

iters = DEFAULT_ITERS
if args.size > 1
  iters = args[1].to_i
if iters <= 0
  << "iterations must be positive"
  exit(2)

parity = 0
if args.size > 2
  if args[2] != "0" && args[2] != "1"
    << "sample parity must be 0 (C/W) or 1 (W/C)"
    exit(2)
  parity = args[2].to_i

run_pair(values, WARMUP_ITERS, parity, false)
run_pair(values, iters, parity)
