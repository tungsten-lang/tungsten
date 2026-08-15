# Closed-world half of method_lock_self_open.w. The child defines no `step`
# override, so after the process-wide method barrier every possible receiver
# of MethodLockSelfCounter#run resolves `self.step` to the same worker.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ MethodLockSelfCounter
  -> step(value)
    value + 1

  -> run(iterations)
    value = 0
    i = 0
    while i < iterations
      value = self.step(value)
      i += 1
    value

+ MethodLockSelfChild < MethodLockSelfCounter

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
counter = MethodLockSelfChild.new()
counter.run(WARMUP_ITERS)
started = clock()
value = counter.run(iterations)
elapsed = clock() - started
<< "RESULT|locked-self|[elapsed * 1_000_000_000 / iterations]|[value]"
