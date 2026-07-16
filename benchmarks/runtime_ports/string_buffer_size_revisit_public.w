# Matched-root public benchmark for StringBuffer#size. The timed selector is
# exactly the public method; the benchmark-only v1 selector records the direct
# raw-i64 return-boundary shape that preceded the inline-i48 production body.

use ../../core/string_buffer

CASE_COUNT = 16
CORPUS_SIZE = 8
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 50_000_000
DEFAULT_OVERFLOW_ITERS = 2_000_000
WARMUP_ITERS = 500_000
OVERFLOW_WARMUP_ITERS = 50_000

+ StringBuffer
  # The baseline core file historically declared lowercase `string_buffer`.
  # Repeating the native view here makes this matched benchmark's unique v1
  # selector available in both roots without changing baseline production.
  - data
    u8     flags
    u8[7]  _pad
    * u8[] data
    i64    length
    i64    capacity

  -> __w_string_buffer_size_v1
    n = $length ## i64
    n

-> build_buffers
  texts = ["", "a", "hello", "0123456789abcdef",
           "\u03bb", "\u03bb\u03bb\u03bb\u03bb", "payload with spaces", "the-end"]
  buffers = []
  i = 0
  while i < texts.size
    buffer = StringBuffer(64)
    ccall("w_strbuf_append", buffer, texts[i])
    buffers.push(buffer)
    i += 1
  buffers

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture(index)
  ccall("w_bench_strbuf_size_fixture", index)

-> raw_size(value)
  ccall_nobox("w_bench_strbuf_raw_size", value) ## i64

-> representation(value)
  ccall("w_bench_strbuf_size_repr", value)

-> dispose_result(value)
  ccall("w_bench_strbuf_size_dispose", value)

-> release_fixture(value)
  ccall("w_bench_strbuf_size_release", value)

-> check_header_case(value, index)
  before = raw_size(value)
  reference = ccall("w_ref_strbuf_size", value)
  v1_result = value.__w_string_buffer_size_v1
  public_result = value.size

  check("header.[index].v1", v1_result, reference)
  check("header.[index].public", public_result, reference)

  reference_repr = representation(reference)
  check("header.[index].repr-v1", representation(v1_result), reference_repr)
  check("header.[index].repr-public", representation(public_result), reference_repr)

  # Immediate Ints have one canonical word. Independently allocated BigInts
  # are pinned by numeric equality and signed limb count above.
  if reference_repr == 0
    reference_bits = wvalue_bits(reference) ## i64
    v1_bits = wvalue_bits(v1_result) ## i64
    public_bits = wvalue_bits(public_result) ## i64
    check("header.[index].bits-v1", v1_bits, reference_bits)
    check("header.[index].bits-public", public_bits, reference_bits)

  check("header.[index].receiver-unchanged", raw_size(value), before)
  dispose_result(reference)
  dispose_result(v1_result)
  dispose_result(public_result)

-> run_correctness
  # Pin every interesting signed-i64 header class, including both i48 edges,
  # their first fallback values, and deliberately corrupt negative headers.
  i = 0
  while i < CASE_COUNT
    value = fixture(i)
    check_header_case(value, i)
    release_fixture(value)
    i += 1

  buffers = build_buffers()
  expected = [0, 1, 5, 16, 2, 8, 19, 7]
  i = 0
  while i < buffers.size
    check("size [i]", buffers[i].size, expected[i])
    check("v1 size [i]", buffers[i].__w_string_buffer_size_v1, expected[i])
    check("representation [i]", type(buffers[i]), "StringBuffer")
    i += 1

  # The native IC ignored surplus args. Type-class dispatch must retain that
  # established behavior after the IC row is removed.
  check("surplus argument", buffers[2].size("ignored"), 5)
  check("v1 surplus argument", buffers[2].__w_string_buffer_size_v1("ignored"), 5)

  live = StringBuffer(1)
  check("fresh", live.size, 0)
  ccall("w_strbuf_append", live, "abc")
  check("after ASCII append", live.size, 3)
  ccall("w_strbuf_append", live, "\u03bb")
  check("after UTF-8 append", live.size, 5)
  check("content stable", live.to_s, "abc\u03bb")
  << "PASS StringBuffer#size (16 signed-i64 headers; exact Int/BigInt representation, live bytes, arity, and receiver stability)"

-> build_overflow_buffers
  # Positive invalid/corrupt headers isolate canonical BigInt fallback without
  # adding negative-size behavior to the timed workload.
  indexes = [9, 10, 14, 9, 10, 14, 9, 10]
  buffers = []
  i = 0
  while i < indexes.size
    buffers.push(fixture(indexes[i]))
    i += 1
  buffers

-> release_fixtures(values)
  i = 0
  while i < values.size
    release_fixture(values[i])
    i += 1

-> time_size(buffers, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_thread_cpu_ns") ## i64
  while i < iters
    checksum += buffers[i & CORPUS_MASK].size
    i += 1
  elapsed = ccall_nobox("w_bench_thread_cpu_ns") - start
  [elapsed, checksum]

-> time_overflow(buffers, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_thread_cpu_ns") ## i64
  while i < iters
    result = buffers[i & CORPUS_MASK].size
    checksum += ccall("w_bench_strbuf_size_consume", result)
    i += 1
  elapsed = ccall_nobox("w_bench_thread_cpu_ns") - start
  [elapsed, checksum]

args = argv()
mode = args.size > 0 ? args[0] : "check"

if mode == "check"
  run_correctness()
  exit(0)

if mode != "hot" && mode != "overflow"
  << "expected: (hot|overflow) POSITIVE_ITERS"
  exit(2)

default_iters = mode == "hot" ? DEFAULT_ITERS : DEFAULT_OVERFLOW_ITERS
iters = args.size > 1 ? args[1].to_i : default_iters
if iters <= 0
  << "expected: (hot|overflow) POSITIVE_ITERS"
  exit(2)

if mode == "hot"
  buffers = build_buffers()
  time_size(buffers, WARMUP_ITERS)
  result = time_size(buffers, iters)
  << "SAMPLE|strbuf.size|[result[0]]|[result[0] * 1.0 / iters]|[result[1]]"
else
  buffers = build_overflow_buffers()
  time_overflow(buffers, OVERFLOW_WARMUP_ITERS)
  result = time_overflow(buffers, iters)
  << "SAMPLE|strbuf.overflow|[result[0]]|[result[0] * 1.0 / iters]|[result[1]]"
  release_fixtures(buffers)
