# Cross-root public-dispatch correctness and timing harness for Float leaves.
# Compile this identical file in the baseline and candidate roots.

use ../../core/float

+ Float
  -> __float_leaf_marker
    self

CASE_COUNT = 20
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
WARMUP_ITERS = 5_000_000

-> float_leaf_case(index)
  ccall("w_ref_float_leaf_case", index)

-> ref_abs(value)
  ccall("w_ref_float_leaf_abs", value)

-> ref_nan(value)
  ccall("w_ref_float_leaf_nan_p", value)

-> ref_infinite(value)
  ccall("w_ref_float_leaf_infinite_p", value)

-> check
  i = 0
  while i < CASE_COUNT
    value = float_leaf_case(i)
    expected_abs = ref_abs(value)
    expected_nan = ref_nan(value)
    expected_infinite = ref_infinite(value)
    marker_result = value.__float_leaf_marker
    if wvalue_bits(marker_result) != wvalue_bits(value)
      << "FAIL Float source marker case=[i]"
      exit(1)
    got_abs = value.abs
    got_nan = value.nan?
    got_infinite = value.infinite?
    if wvalue_bits(got_abs) != wvalue_bits(expected_abs)
      << "FAIL abs case=[i] got=[wvalue_bits(got_abs)] expected=[wvalue_bits(expected_abs)]"
      exit(1)
    if got_nan != expected_nan
      << "FAIL nan? case=[i] got=[got_nan] expected=[expected_nan]"
      exit(1)
    if got_infinite != expected_infinite
      << "FAIL infinite? case=[i] got=[got_infinite] expected=[expected_infinite]"
      exit(1)
    i += 1
  << "correctness: ok ([CASE_COUNT * 3] public checks, including raw noncanonical NaNs)"

-> corpus_for(kind)
  if kind == "abs-finite"
    indexes = [6, 7, 8, 9, 10, 11, 20, 21,
               7, 6, 9, 8, 11, 10, 21, 20]
  elsif kind == "abs-edge"
    indexes = [0, 1, 2, 3, 4, 5, 16, 17,
               1, 0, 3, 2, 5, 4, 17, 16]
  elsif kind == "abs-nan"
    indexes = [12, 13, 14, 15, 18, 19, 12, 18,
               13, 19, 14, 18, 15, 19, 12, 19]
  elsif kind == "nan?"
    indexes = [0, 12, 1, 13, 2, 14, 3, 15,
               6, 18, 7, 19, 10, 12, 16, 13]
  elsif kind == "infinite?"
    indexes = [0, 16, 1, 17, 2, 16, 3, 17,
               6, 16, 7, 17, 12, 16, 14, 17]
  else
    << "unknown benchmark kind: [kind]"
    exit(2)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_leaf_case(indexes[i]))
    i += 1
  values

-> thread_cpu_ns
  ccall("w_runtime_port_thread_cpu_ns")

-> time_abs(values, iters)
  checksum = 0
  i = 0
  start_ns = thread_cpu_ns()
  while i < iters
    result = values[i & CORPUS_MASK].abs
    checksum += (wvalue_bits(result) >> 32) & 0xFFFF
    i += 1
  [thread_cpu_ns() - start_ns, checksum]

-> time_nan(values, iters)
  checksum = 0
  i = 0
  start_ns = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].nan? ? 1 : 0
    i += 1
  [thread_cpu_ns() - start_ns, checksum]

-> time_infinite(values, iters)
  checksum = 0
  i = 0
  start_ns = thread_cpu_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].infinite? ? 1 : 0
    i += 1
  [thread_cpu_ns() - start_ns, checksum]

-> run_once(kind, values, iters)
  if kind in ("abs-finite" "abs-edge" "abs-nan")
    time_abs(values, iters)
  elsif kind == "nan?"
    time_nan(values, iters)
  else
    time_infinite(values, iters)

args = argv()
mode = args.size > 0 ? args[0] : "check"
if mode == "check"
  check()
  exit(0)
if mode != "bench" || args.size < 3
  << "usage: float-leaf-public bench KIND ITERS"
  exit(2)
kind = args[1]
iters = args[2].to_i
values = corpus_for(kind)
run_once(kind, values, WARMUP_ITERS)
result = run_once(kind, values, iters)
<< "RESULT|[kind]|[result[0]]|[result[1]]"
