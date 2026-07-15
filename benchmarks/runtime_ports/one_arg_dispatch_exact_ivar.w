# Production-shaped benchmark for the exact-source ivar argc-one dispatch
# proof. Every write to @receiver constructs the same ordinary source class,
# so the compiler can use the scalar source-method cache without relying on a
# flow-insensitive local type.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ ExactIvarDispatchTarget
  -> echo(value)
    value

+ ExactIvarDispatchHolder
  -> new
    @receiver = ExactIvarDispatchTarget.new()

  -> time(iterations)
    checksum = 0
    i = 0
    started = exact_ivar_dispatch_cpu_clock()
    while i < iterations
      argument = i & 1023
      checksum += @receiver.echo(argument)
      i += 1
    [exact_ivar_dispatch_cpu_clock() - started, checksum]

-> exact_ivar_dispatch_cpu_clock
  ccall("w_bench_one_arg_thread_cpu_clock")

-> exact_ivar_repeating_sum(iterations)
  cycles = iterations / 1024
  remainder = iterations % 1024
  cycles * 523776 + remainder * (remainder - 1) / 2

args = argv()
iterations = args.size() > 0 ? args[0].to_i : DEFAULT_ITERS
if iterations <= 0
  << "usage: one_arg_dispatch_exact_ivar POSITIVE_ITERS"
  exit(2)

holder = ExactIvarDispatchHolder.new()
holder.time(WARMUP_ITERS)
result = holder.time(iterations)
expected = exact_ivar_repeating_sum(iterations)
if result[1] != expected
  << "FAIL exact-ivar argc-one checksum=[result[1]] expected=[expected]"
  exit(1)

ns = result[0] * 1_000_000_000 / iterations
<< "RESULT|exact-ivar|[ns]|[result[1]]"
