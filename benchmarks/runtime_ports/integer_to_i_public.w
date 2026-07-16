# Production-shaped Integer#to_i public-dispatch benchmark. Compile this same
# source against isolated native-IC and source-method roots. There is no
# explicit Integer import: the candidate's call-name autoload must work.

CORPUS_MASK = 15
DEFAULT_ITERS = 50_000_000
DEFAULT_WARMUP = 1_000_000

-> thread_time_ns
  ccall("w_runtime_port_thread_cpu_ns")

-> corpus
  [-140_737_488_355_328, -140_737_488_355_327,
   -1_000_003, -257, -3, -2, -1, 0,
   1, 2, 3, 256, 1_000_003,
   140_737_488_355_326, 140_737_488_355_327, 42]

-> fail(name, index, got, want)
  << "FAIL int to_i [name] index=[index] got=[got] want=[want]"
  exit(1)

-> check_equal(name, index, got, want)
  if got != want
    fail(name, index, got, want)

-> run_checks
  values = corpus()
  i = 0
  while i < values.size
    value = values[i]
    plain = value.to_i
    extra_one = value.to_i(99)
    extra_many = value.to_i(1, 2, 3)
    check_equal("plain value", i, plain, value)
    check_equal("plain bits", i, wvalue_bits(plain), wvalue_bits(value))
    check_equal("one extra value", i, extra_one, value)
    check_equal("one extra bits", i, wvalue_bits(extra_one), wvalue_bits(value))
    check_equal("many extra value", i, extra_many, value)
    check_equal("many extra bits", i, wvalue_bits(extra_many), wvalue_bits(value))
    i += 1

  hits = 0
  values[10].to_i -> (ignored)
    hits += 1
  check_equal("trailing block passthrough", 0, hits, 3)
  << "PASS Integer#to_i exact public semantics"

-> time_varying(values, iters)
  checksum = 0
  i = 0
  started = thread_time_ns()
  while i < iters
    checksum += values[i & CORPUS_MASK].to_i & 0xFF
    i += 1
  [thread_time_ns() - started, checksum]

-> time_inferred(iters)
  checksum = 0
  i = 0
  started = thread_time_ns()
  while i < iters
    value = (i & 1023) - 512
    checksum += value.to_i & 0xFF
    i += 1
  [thread_time_ns() - started, checksum]

args = argv()
mode = args.size > 0 ? args[0] : "check"
run_checks()
if mode == "bench"
  iters = args.size > 1 ? args[1].to_i : DEFAULT_ITERS
  warmup = args.size > 2 ? args[2].to_i : DEFAULT_WARMUP
  values = corpus()
  time_varying(values, warmup)
  time_inferred(warmup)
  varying = time_varying(values, iters)
  inferred = time_inferred(iters)
  << "RESULT|varying|[varying[0]]|[varying[1]]"
  << "RESULT|inferred|[inferred[0]]|[inferred[1]]"
