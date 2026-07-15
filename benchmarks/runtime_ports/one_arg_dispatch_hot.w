# Cross-build production-shaped benchmark for a compiler-emitted one-argument
# dispatch ABI. Compile this unchanged source with isolated baseline and
# candidate roots. Unlike one_arg_dispatch_ab, each hot call is emitted by the
# Tungsten compiler and its argument changes on every loop iteration, so the
# baseline cannot hoist the argument store out of the measured loop.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ OneArgDispatchHotTarget
  -> echo(value)
    value

# These functions intentionally contain a dynamic argc-one call and no
# larger-arity dynamic call. A production candidate should therefore remove
# both the per-iteration store and the function's %__mcall_args alloca.
-> time_source(receiver, iterations)
  checksum = 0
  i = 0
  started = clock()
  while i < iterations
    argument = i & 1023
    checksum += receiver.echo(argument)
    i += 1
  [clock() - started, checksum]

-> time_native(receiver, iterations)
  checksum = 0
  i = 0
  started = clock()
  while i < iterations
    argument = i & 7
    checksum += receiver.get(argument)
    i += 1
  [clock() - started, checksum]

-> repeating_sum(iterations, period, cycle_sum)
  cycles = iterations / period
  remainder = iterations % period
  cycles * cycle_sum + remainder * (remainder - 1) / 2

-> expected_source(iterations)
  repeating_sum(iterations, 1024, 523776)

-> expected_native(iterations)
  repeating_sum(iterations, 8, 28)

args = argv()
mode = args.size() > 0 ? args[0] : "source1"
iterations = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS

if iterations <= 0 || (mode != "source1" && mode != "native1" && mode != "check")
  << "usage: one_arg_dispatch_hot (source1|native1|check) POSITIVE_ITERS"
  exit(2)

source_receiver = OneArgDispatchHotTarget.new()
native_receiver = [0, 1, 2, 3, 4, 5, 6, 7]

if mode == "check"
  check_iterations = 1027
  source_result = time_source(source_receiver, check_iterations)
  native_result = time_native(native_receiver, check_iterations)
  if source_result[1] != expected_source(check_iterations)
    << "FAIL source argc-one production-call correctness"
    exit(1)
  if native_result[1] != expected_native(check_iterations)
    << "FAIL native argc-one production-call correctness"
    exit(1)
  << "correctness: ok"
  exit(0)

if mode == "source1"
  time_source(source_receiver, WARMUP_ITERS)
  result = time_source(source_receiver, iterations)
  expected = expected_source(iterations)
else
  time_native(native_receiver, WARMUP_ITERS)
  result = time_native(native_receiver, iterations)
  expected = expected_native(iterations)

if result[1] != expected
  << "FAIL [mode] checksum=[result[1]] expected=[expected]"
  exit(1)

ns = result[0] * 1_000_000_000 / iterations
<< "RESULT|[mode]|[ns]|[result[1]]"
