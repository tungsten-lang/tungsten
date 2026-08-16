# Return class-set SCC benchmark. The parent compiler cannot carry the
# Dog-or-Cat result through either recursive component, so the hot `step` calls
# retain an inline cache. The class-set-summary compiler emits an exhaustive
# class decision with direct-call arms. Object construction happens before the
# timed loops.

DEFAULT_ITERS = 100_000_000
WARMUP_ITERS = 5_000_000

+ ReturnSetBenchDog
  -> step(value)
    value + 1

+ ReturnSetBenchCat
  -> step(value)
    value + 2

-> function_factory_a(choose_dog, depth)
  if depth > 0
    function_factory_b(choose_dog, depth - 1)
  elsif choose_dog
    ReturnSetBenchDog.new()
  else
    ReturnSetBenchCat.new()

-> function_factory_b(choose_dog, depth)
  if depth > 0
    function_factory_a(choose_dog, depth - 1)
  elsif choose_dog
    ReturnSetBenchDog.new()
  else
    ReturnSetBenchCat.new()

+ ReturnSetBenchFactory
  -> method_factory_a(choose_dog, depth)
    if depth > 0
      method_factory_b(choose_dog, depth - 1)
    elsif choose_dog
      ReturnSetBenchDog.new()
    else
      ReturnSetBenchCat.new()

  -> method_factory_b(choose_dog, depth)
    if depth > 0
      method_factory_a(choose_dog, depth - 1)
    elsif choose_dog
      ReturnSetBenchDog.new()
    else
      ReturnSetBenchCat.new()

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
iterations = args.size() > 0 ? args[0].to_i() : DEFAULT_ITERS
choose_dog = args.size() > 1

function_counter = function_factory_a(choose_dog, 1)
method_counter = ReturnSetBenchFactory.new().method_factory_a(choose_dog, 1)

value = 0
i = 0
while i < WARMUP_ITERS
  value = function_counter.step(value)
  i += 1

started = clock()
value = 0
i = 0
while i < iterations
  value = function_counter.step(value)
  i += 1
function_elapsed = clock() - started

value = 0
i = 0
while i < WARMUP_ITERS
  value = method_counter.step(value)
  i += 1

started = clock()
value = 0
i = 0
while i < iterations
  value = method_counter.step(value)
  i += 1
method_elapsed = clock() - started

<< "RESULT|return_class_set_function_scc|[function_elapsed * 1_000_000_000 / iterations]|[value]"
<< "RESULT|return_class_set_method_scc|[method_elapsed * 1_000_000_000 / iterations]|[value]"
