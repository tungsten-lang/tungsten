# Cross-build benchmark for the compiler-emitted zero-argument dispatch ABI.
# Compile this unchanged source with baseline and candidate compilers/runtimes;
# emitted calls are the only difference between the resulting hot loops.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ ZeroArgDispatchHotTarget
  -> answer
    7

-> dynamic_answer(receiver)
  receiver.answer()

-> dynamic_size(receiver)
  receiver.size()

-> time_source(receiver, iterations)
  checksum = 0
  i = 0
  started = clock()
  while i < iterations
    checksum += dynamic_answer(receiver)
    i += 1
  [clock() - started, checksum]

-> time_native(receiver, iterations)
  checksum = 0
  i = 0
  started = clock()
  while i < iterations
    checksum += dynamic_size(receiver)
    i += 1
  [clock() - started, checksum]

args = argv()
mode = args.size() > 0 ? args[0] : "source0"
iterations = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS

if iterations <= 0 || (mode != "source0" && mode != "native0" && mode != "check")
  << "usage: zero_arg_dispatch_hot (source0|native0|check) POSITIVE_ITERS"
  exit(2)

source_receiver = ZeroArgDispatchHotTarget.new()
native_receiver = [0, 1, 2, 3, 4, 5, 6, 7]

if mode == "check"
  if dynamic_answer(source_receiver) != 7 || dynamic_size(native_receiver) != 8
    << "FAIL zero-argument production-call correctness"
    exit(1)
  << "correctness: ok"
  exit(0)

if mode == "source0"
  time_source(source_receiver, WARMUP_ITERS)
  result = time_source(source_receiver, iterations)
  expected = iterations * 7
else
  time_native(native_receiver, WARMUP_ITERS)
  result = time_native(native_receiver, iterations)
  expected = iterations * 8

if result[1] != expected
  << "FAIL [mode] checksum=[result[1]] expected=[expected]"
  exit(1)

ns = result[0] * 1_000_000_000 / iterations
<< "RESULT|[mode]|[ns]|[result[1]]"
