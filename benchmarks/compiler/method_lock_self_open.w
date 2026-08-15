# Open-world half of method_lock_self_locked.w. The hot call is `self.step`
# inside a base method running on a child instance; it must retain guarded
# dispatch while method definitions remain open.

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

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
counter = MethodLockSelfChild.new()
counter.run(WARMUP_ITERS)
started = clock()
value = counter.run(iterations)
elapsed = clock() - started
<< "RESULT|open-self|[elapsed * 1_000_000_000 / iterations]|[value]"
