# Open-world half of method_lock_locked.w. Keep the workload identical: this
# build retains the exact-class guard and inline-cache fallback.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ MethodLockCounter
  -> step(value)
    value + 1

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
counter = MethodLockCounter.new()
value = 0
i = 0
while i < WARMUP_ITERS
  value = counter.step(value)
  i += 1
started = clock()
value = 0
i = 0
while i < iterations
  value = counter.step(value)
  i += 1
elapsed = clock() - started
<< "RESULT|open|[elapsed * 1_000_000_000 / iterations]|[value]"
