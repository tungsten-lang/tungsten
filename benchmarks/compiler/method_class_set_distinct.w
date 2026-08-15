# Two-target twin of method_class_set_shared.w. The parent compiler retains a
# guarded IC; the class-set compiler emits an exhaustive class decision whose
# two arms call the permanent workers directly.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ ClassSetDistinctDog
  -> step(value)
    value + 1

+ ClassSetDistinctCat
  -> step(value)
    value + 2

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
choose_dog = args.size() > 1
if choose_dog
  counter = ClassSetDistinctDog.new()
else
  counter = ClassSetDistinctCat.new()

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
<< "RESULT|class_set_distinct|[elapsed * 1_000_000_000 / iterations]|[value]"
