# Production-shaped stress test for the argc-one helper's compatibility path.
# The else branch deliberately leaves lowering's conservative local type fact
# as StaleArgcOneTarget, while the true branch supplies a prebuilt Array at
# runtime. This is the same stale-type shape covered by the compatibility spec,
# but keeps allocation outside the timed loop so dispatch cost is measurable.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ StaleArgcOneTarget
  -> get(index)
    index + 100

-> stale_dispatch_cpu_clock
  ccall("w_bench_one_arg_thread_cpu_clock")

-> time_stale_native(native_receiver, iterations)
  receiver = StaleArgcOneTarget.new()
  checksum = 0
  i = 0
  started = stale_dispatch_cpu_clock()
  while i < iterations
    if i >= 0
      receiver = native_receiver
    else
      receiver = StaleArgcOneTarget.new()
    argument = i & 7
    checksum += receiver.get(argument)
    i += 1
  [stale_dispatch_cpu_clock() - started, checksum]

-> repeating_sum(iterations, period, cycle_sum)
  cycles = iterations / period
  remainder = iterations % period
  cycles * cycle_sum + remainder * (remainder - 1) / 2

args = argv()
iterations = args.size() > 0 ? args[0].to_i : DEFAULT_ITERS
if iterations <= 0
  << "usage: one_arg_dispatch_stale_hot POSITIVE_ITERS"
  exit(2)

native_receiver = [0, 1, 2, 3, 4, 5, 6, 7]
time_stale_native(native_receiver, WARMUP_ITERS)
result = time_stale_native(native_receiver, iterations)
expected = repeating_sum(iterations, 8, 28)
if result[1] != expected
  << "FAIL stale argc-one checksum=[result[1]] expected=[expected]"
  exit(1)

ns = result[0] * 1_000_000_000 / iterations
<< "RESULT|stale-native|[ns]|[result[1]]"
