# Matched-root public benchmark for Mmap#size. Public size is the only timed
# selector and the native reference is kept under a unique method name.

use ../../core/file

CASE_COUNT = 16
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_INLINE_ITERS = 50_000_000
DEFAULT_OVERFLOW_ITERS = 2_000_000
INLINE_WARMUP_ITERS = 500_000
OVERFLOW_WARMUP_ITERS = 50_000

+ Mmap
  -> __c_mmap_size_relaxed
    ccall("w_ref_mmap_size_relaxed", self)

-> fail_check(name, detail)
  << "FAIL [name]: [detail]"
  exit(1)

-> check(name, got, expected)
  if got != expected
    fail_check(name, "got=[got] expected=[expected]")

-> fixture(index)
  ccall("w_bench_mmap_size_relaxed_fixture", index)

-> raw_size(value)
  ccall_nobox("w_bench_mmap_size_relaxed_raw", value) ## i64

-> representation(value)
  ccall("w_bench_mmap_size_relaxed_repr", value)

-> dispose_result(value)
  ccall("w_bench_mmap_size_relaxed_dispose", value)

-> release_fixture(value)
  ccall("w_bench_mmap_size_relaxed_release", value)

-> check_header(value, index)
  before = raw_size(value)
  reference = value.__c_mmap_size_relaxed
  public_result = value.size

  check("header.[index].public", public_result, reference)
  reference_repr = representation(reference)
  check("header.[index].repr-public", representation(public_result), reference_repr)
  if reference_repr == 0
    reference_bits = wvalue_bits(reference) ## i64
    public_bits = wvalue_bits(public_result) ## i64
    check("header.[index].bits-public", public_bits, reference_bits)
  check("header.[index].receiver", raw_size(value), before)

  dispose_result(reference)
  dispose_result(public_result)

-> run_correctness
  i = 0
  while i < CASE_COUNT
    value = fixture(i)
    check_header(value, i)
    release_fixture(value)
    i += 1

  zero = fixture(0)
  check("arity.reference", zero.__c_mmap_size_relaxed(123), 0)
  check("arity.public", zero.size(123), 0)
  release_fixture(zero)

  # Pin the no-block method's established trailing-block passthrough without
  # assuming its return convention: the native reference is authoritative.
  seven = fixture(2)
  reference_hits = 0
  reference_return = seven.__c_mmap_size_relaxed -> reference_hits += 1
  public_hits = 0
  public_return = seven.size -> public_hits += 1
  check("block.public.hits", public_hits, reference_hits)
  check("block.public.return", public_return, reference_return)
  release_fixture(seven)

  # Real mappings retain size after close; the source load must not introduce
  # a closed-state check that the native method never had.
  real = File.mmap("VERSION")
  expected = real.__c_mmap_size_relaxed
  check("real.before.public", real.size, expected)
  real.close
  check("real.after.public", real.size, expected)
  << "PASS Mmap#size relaxed (16 signed-i64 headers; exact representation, arity/block, close stability, and ABI layout)"

-> build_inline_corpus
  indexes = [0, 1, 2, 3, 4, 5, 6, 7,
             8, 6, 5, 4, 3, 2, 1, 0]
  values = []
  i = 0
  while i < indexes.size
    values.push(fixture(indexes[i]))
    i += 1
  values

-> build_overflow_corpus
  indexes = [9, 10, 14, 9, 10, 14, 9, 10,
             14, 10, 9, 14, 10, 9, 14, 10]
  values = []
  i = 0
  while i < indexes.size
    values.push(fixture(indexes[i]))
    i += 1
  values

-> release_corpus(values)
  i = 0
  while i < values.size
    release_fixture(values[i])
    i += 1

-> time_inline(values, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_mmap_relaxed_thread_cpu_ns") ## i64
  while i < iters
    checksum += values[i & CORPUS_MASK].size & 0xFF
    i += 1
  elapsed = ccall_nobox("w_bench_mmap_relaxed_thread_cpu_ns") - start
  [elapsed, checksum]

-> time_overflow(values, iters)
  checksum = 0
  i = 0
  start = ccall_nobox("w_bench_mmap_relaxed_thread_cpu_ns") ## i64
  while i < iters
    result = values[i & CORPUS_MASK].size
    checksum += ccall("w_bench_mmap_size_relaxed_consume", result)
    i += 1
  elapsed = ccall_nobox("w_bench_mmap_relaxed_thread_cpu_ns") - start
  [elapsed, checksum]

args = argv()
mode = args.size > 0 ? args[0] : "check"
if mode == "check"
  run_correctness()
  exit(0)

if mode != "inline" && mode != "overflow"
  << "expected: (inline|overflow) POSITIVE_ITERS"
  exit(2)

default_iters = mode == "inline" ? DEFAULT_INLINE_ITERS : DEFAULT_OVERFLOW_ITERS
iters = args.size > 1 ? args[1].to_i : default_iters
if iters <= 0
  << "expected: (inline|overflow) POSITIVE_ITERS"
  exit(2)

values = mode == "inline" ? build_inline_corpus() : build_overflow_corpus()
if mode == "inline"
  time_inline(values, INLINE_WARMUP_ITERS)
  result = time_inline(values, iters)
  << "SAMPLE|mmap.size|[result[0]]|[result[0] * 1.0 / iters]|[result[1]]"
else
  time_overflow(values, OVERFLOW_WARMUP_ITERS)
  result = time_overflow(values, iters)
  << "SAMPLE|mmap.overflow|[result[0]]|[result[0] * 1.0 / iters]|[result[1]]"
release_corpus(values)
