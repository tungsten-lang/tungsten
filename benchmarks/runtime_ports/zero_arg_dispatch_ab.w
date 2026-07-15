# Exact in-process comparison of the generic cached dispatcher against the
# argc-zero entry point.  `source0` exercises cache arity 0; `native0`
# exercises a native wrapper's arity -1 branch.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ ZeroArgDispatchBenchTarget
  -> answer
    7

-> call_generic(receiver, name, iterations, slot)
  ccall("w_bench_zero_arg_generic", receiver, name, iterations, slot)

-> call_specialized(receiver, name, iterations, slot)
  ccall("w_bench_zero_arg_specialized", receiver, name, iterations, slot)

-> timed_generic(receiver, name, iterations, slot)
  started = clock()
  value = call_generic(receiver, name, iterations, slot)
  [clock() - started, value]

-> timed_specialized(receiver, name, iterations, slot)
  started = clock()
  value = call_specialized(receiver, name, iterations, slot)
  [clock() - started, value]

-> run_single_pair(receiver, name, iterations, slot, parity)
  if parity == 0
    generic = timed_generic(receiver, name, iterations, slot)
    specialized = timed_specialized(receiver, name, iterations, slot)
  else
    specialized = timed_specialized(receiver, name, iterations, slot)
    generic = timed_generic(receiver, name, iterations, slot)
  [generic, specialized]

-> run_pair(label, receiver, name, expected, iterations, slot, parity, emit = true)
  # One process runs generic/zero/zero/generic or its reverse.  Summed times
  # cancel first-order frequency and thermal drift.
  first = run_single_pair(receiver, name, iterations, slot, parity)
  second = run_single_pair(receiver, name, iterations, slot, parity == 0 ? 1 : 0)
  generic_seconds = first[0][0] + second[0][0]
  specialized_seconds = first[1][0] + second[1][0]
  results_match = first[0][1] == expected && first[1][1] == expected
  results_match = results_match && second[0][1] == expected
  results_match = results_match && second[1][1] == expected
  if !results_match
    << "FAIL [label] result mismatch"
    exit(1)
  if emit
    calls = iterations * 2
    generic_ns = generic_seconds * 1_000_000_000 / calls
    specialized_ns = specialized_seconds * 1_000_000_000 / calls
    ratio = specialized_seconds / generic_seconds
    << "RESULT|[label]|[generic_ns]|[specialized_ns]|[ratio]|[expected]"

-> run_correctness(source_receiver, native_receiver)
  source_ok = call_generic(source_receiver, "answer", 3, 0) == 7
  source_ok = source_ok && call_specialized(source_receiver, "answer", 3, 0) == 7
  if !source_ok
    << "FAIL source arity-zero correctness"
    exit(1)
  native_ok = call_generic(native_receiver, "size", 3, 1) == 8
  native_ok = native_ok && call_specialized(native_receiver, "size", 3, 1) == 8
  if !native_ok
    << "FAIL native arity-minus-one correctness"
    exit(1)
  << "correctness: ok (generic and specialized; source arity 0 and native arity -1)"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
iterations = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS
parity = args.size() > 2 ? args[2].to_i : 0
only = args.size() > 3 ? args[3] : ""

source_receiver = ZeroArgDispatchBenchTarget.new()
native_receiver = [0, 1, 2, 3, 4, 5, 6, 7]

if mode == "check"
  run_correctness(source_receiver, native_receiver)
  exit(0)

if iterations <= 0 || (parity != 0 && parity != 1)
  << "usage: zero_arg_dispatch_ab bench POSITIVE_ITERS (0|1) [source0|native0]"
  exit(2)

if only == "" || only == "source0"
  run_pair("source0", source_receiver, "answer", 7,
           WARMUP_ITERS, 0, parity, false)
if only == "" || only == "native0"
  run_pair("native0", native_receiver, "size", 8,
           WARMUP_ITERS, 1, parity, false)

if only == "" || only == "source0"
  run_pair("source0", source_receiver, "answer", 7,
           iterations, 0, parity)
if only == "" || only == "native0"
  run_pair("native0", native_receiver, "size", 8,
           iterations, 1, parity)
