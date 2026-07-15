# Same-binary BigArray#size migration gate. The C leg mirrors the installed
# handler; v1 uses the ordinary raw-i64 boxing boundary; v2 inlines its common
# i48 arm. Public `size` remains the production C IC during this first gate.

use big_array_size_candidates

CASE_COUNT = 16
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_INLINE_ITERS = 50_000_000
DEFAULT_OVERFLOW_ITERS = 2_000_000

+ BigArray
  -> __c_big_array_size
    ccall("w_ref_big_array_size", self)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check_value(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture(index)
  ccall("w_bench_big_array_size_fixture", index)

-> raw_size(value)
  ccall_nobox("w_bench_big_array_raw_size", value) ## i64

-> representation(value)
  ccall("w_bench_big_array_size_repr", value)

-> dispose_result(value)
  ccall("w_bench_big_array_size_dispose", value)

-> release_fixture(value)
  ccall("w_bench_big_array_size_release", value)

-> check_case(value, index)
  before = raw_size(value)
  c_result = value.__c_big_array_size
  v1_result = value.__w_big_array_size_v1
  v2_result = value.__w_big_array_size_v2
  public_result = value.size

  check_value("case.[index].c-v1", v1_result, c_result)
  check_value("case.[index].c-v2", v2_result, c_result)
  check_value("case.[index].c-public", public_result, c_result)

  c_repr = representation(c_result)
  check_value("case.[index].repr-v1", representation(v1_result), c_repr)
  check_value("case.[index].repr-v2", representation(v2_result), c_repr)
  check_value("case.[index].repr-public", representation(public_result), c_repr)

  # Immediate results have one canonical bit pattern. Heap BigInts are fresh
  # objects, so numeric equality plus signed limb count is the exact stable
  # representation comparison available across independent calls.
  if c_repr == 0
    c_bits = wvalue_bits(c_result) ## i64
    v1_bits = wvalue_bits(v1_result) ## i64
    v2_bits = wvalue_bits(v2_result) ## i64
    public_bits = wvalue_bits(public_result) ## i64
    check_value("case.[index].bits-v1", v1_bits, c_bits)
    check_value("case.[index].bits-v2", v2_bits, c_bits)
    check_value("case.[index].bits-public", public_bits, c_bits)

  check_value("case.[index].receiver-unchanged", raw_size(value), before)

  dispose_result(c_result)
  dispose_result(v1_result)
  dispose_result(v2_result)
  dispose_result(public_result)

-> run_correctness
  i = 0
  while i < CASE_COUNT
    value = fixture(i)
    check_case(value, i)
    release_fixture(value)
    i += 1

  # The native IC ignores extra positional arguments. A trailing block on this
  # no-block method is handled by the compiled call-site surface and currently
  # yields nil for the zero result; pin both behaviors because a public
  # migration must not quietly narrow that historical call surface.
  zero = fixture(0)
  check_value("arity.c-extra", zero.__c_big_array_size(123), 0)
  check_value("arity.v1-extra", zero.__w_big_array_size_v1(123), 0)
  check_value("arity.v2-extra", zero.__w_big_array_size_v2(123), 0)
  check_value("arity.public-extra", zero.size(123), 0)
  block_c = zero.__c_big_array_size -> 99
  block_v1 = zero.__w_big_array_size_v1 -> 99
  block_v2 = zero.__w_big_array_size_v2 -> 99
  block_public = zero.size -> 99
  check_value("block.c", block_c, nil)
  check_value("block.v1", block_v1, block_c)
  check_value("block.v2", block_v2, block_c)
  check_value("block.public", block_public, block_c)
  release_fixture(zero)

  << "correctness: ok ([CASE_COUNT] signed-i64 header patterns; exact Int/BigInt representation, extra-argument/block truncation, and receiver stability)"

-> build_inline_corpus
  # All entries stay in i48 while spanning byte-size, 2^32, and the positive
  # i48 edge. The mask keeps the timed checksum small and nonallocating.
  indexes = [0, 1, 2, 3, 4, 5, 6, 7,
             8, 6, 5, 4, 3, 2, 1, 0]
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(fixture(indexes[i]))
    i += 1
  values

-> build_overflow_corpus
  # Positive overflow is valid for an i64-sized borrowed view. These exercise
  # canonical BigInt fallback without conflating the benchmark with invalid
  # negative-size fixtures.
  indexes = [9, 10, 14, 9, 10, 14, 9, 10,
             14, 10, 9, 14, 10, 9, 14, 10]
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(fixture(indexes[i]))
    i += 1
  values

-> release_corpus(values)
  i = 0
  while i < values.size
    release_fixture(values[i])
    i += 1

-> finish_timing(start_ns, checksum)
  [clock() - start_ns, checksum]

-> time_inline_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__c_big_array_size & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_inline_v1(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_big_array_size_v1 & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_inline_v2(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    checksum += values[i & CORPUS_MASK].__w_big_array_size_v2 & 0xFF
    i += 1
  finish_timing(start_ns, checksum)

-> time_overflow_c(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__c_big_array_size
    checksum += ccall("w_bench_big_array_size_consume", result)
    i += 1
  finish_timing(start_ns, checksum)

-> time_overflow_v1(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__w_big_array_size_v1
    checksum += ccall("w_bench_big_array_size_consume", result)
    i += 1
  finish_timing(start_ns, checksum)

-> time_overflow_v2(values, iters)
  checksum = 0
  i = 0
  start_ns = clock()
  while i < iters
    result = values[i & CORPUS_MASK].__w_big_array_size_v2
    checksum += ccall("w_bench_big_array_size_consume", result)
    i += 1
  finish_timing(start_ns, checksum)

-> time_c(values, iters, stratum)
  stratum == "inline" ? time_inline_c(values, iters) : time_overflow_c(values, iters)

-> time_w(values, iters, path, stratum)
  if path == "v1"
    return stratum == "inline" ? time_inline_v1(values, iters) : time_overflow_v1(values, iters)
  stratum == "inline" ? time_inline_v2(values, iters) : time_overflow_v2(values, iters)

-> add_timing(a, b)
  [a[0] + b[0], a[1] + b[1]]

-> report_result(path, stratum, c_result, w_result, iters)
  if c_result[1] != w_result[1]
    fail_check("benchmark-checksum.[path].[stratum]", "C=[c_result[1]] W=[w_result[1]]")
  legs = iters * 2
  c_ns = c_result[0] * 1_000_000_000 / legs
  w_ns = w_result[0] * 1_000_000_000 / legs
  ratio = w_result[0] / c_result[0]
  << "RESULT|size.[path].[stratum]|[c_ns]|[w_ns]|[ratio]|[c_result[1]]"

-> run_balanced(values, iters, parity, path, stratum, emit = true)
  # One process supplies a balanced C/W/W/C or W/C/C/W observation.
  if parity == 0
    c_first = time_c(values, iters, stratum)
    w_first = time_w(values, iters, path, stratum)
    w_second = time_w(values, iters, path, stratum)
    c_second = time_c(values, iters, stratum)
  else
    w_first = time_w(values, iters, path, stratum)
    c_first = time_c(values, iters, stratum)
    c_second = time_c(values, iters, stratum)
    w_second = time_w(values, iters, path, stratum)
  c_result = add_timing(c_first, c_second)
  w_result = add_timing(w_first, w_second)
  if emit
    report_result(path, stratum, c_result, w_result, iters)

args = argv()
mode = args.size > 0 ? args[0] : "check"

if mode == "check"
  run_correctness()
  exit(0)

if mode != "bench" || args.size < 6
  << "usage: big-array-size-ab bench STRATUM ITERS WARMUP PARITY PATH"
  exit(2)

stratum = args[1]
if stratum != "inline" && stratum != "overflow"
  << "stratum must be inline or overflow"
  exit(2)
iters = args[2].to_i
warmup = args[3].to_i
parity = args[4].to_i
path = args[5]
if iters <= 0 || warmup <= 0
  << "iterations and warmup must be positive"
  exit(2)
if parity != 0 && parity != 1
  << "parity must be 0 or 1"
  exit(2)
if path != "v1" && path != "v2"
  << "path must be v1 or v2"
  exit(2)

values = stratum == "inline" ? build_inline_corpus() : build_overflow_corpus()
run_balanced(values, warmup, parity, path, stratum, false)
run_balanced(values, iters, parity, path, stratum)
release_corpus(values)
