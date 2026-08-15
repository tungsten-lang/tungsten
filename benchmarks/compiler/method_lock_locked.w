# Closed-world half of method_lock_open.w. The executable owner validates Core
# provenance, then irreversibly closes all method tables before execution.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ MethodLockCounter
  -> step(value)
    value + 1

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

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
<< "RESULT|locked|[elapsed * 1_000_000_000 / iterations]|[value]"
