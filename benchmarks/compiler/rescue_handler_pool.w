DEFAULT_ITERS = 5_000_000
WARMUP_ITERS = 100_000

+ RescueHandlerPoolBench
  -> run(iterations)
    total = 0
    i = 0
    while i < iterations
      begin
        total += 1
      rescue error
        total -= 1
      i += 1
    total

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
bench = RescueHandlerPoolBench.new()
bench.run(WARMUP_ITERS)
started = clock()
value = bench.run(iterations)
elapsed = clock() - started
<< "RESULT|rescue-handler|[elapsed * 1_000_000_000 / iterations]|[value]"
