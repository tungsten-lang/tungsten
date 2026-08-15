# Flow-sensitive class-set dispatch benchmark. Compile this same source with a
# parent compiler and the class-set compiler; LOCK_THE_DOORS is present in both
# binaries, so the only hot-loop difference is the dispatch proof.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ ClassSetSharedBase
  -> step(value)
    value + 1

+ ClassSetSharedDog < ClassSetSharedBase

+ ClassSetSharedCat < ClassSetSharedBase

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
choose_dog = args.size() > 1
if choose_dog
  counter = ClassSetSharedDog.new()
else
  counter = ClassSetSharedCat.new()

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
<< "RESULT|class_set_shared|[elapsed * 1_000_000_000 / iterations]|[value]"
