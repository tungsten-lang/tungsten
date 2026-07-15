# Dispatcher-only in-process comparison of generic cached dispatch against a
# narrow argc-one candidate. `source1` exercises cache arity 1; `native1`
# exercises a native wrapper's arity -1 branch. The generic C loop hoists its
# one-element argument array, so this intentionally excludes the production
# emitter's argument-store and scratch-alloca savings.

DEFAULT_ITERS = 50_000_000
WARMUP_ITERS = 5_000_000

+ OneArgDispatchBenchTarget
  -> echo(value)
    value

  -> no_args
    13

  -> with_default(left, right = 27)
    left + right

  -> with_three(first, second = 11, third = 19)
    first + second + third

  -> with_four(first, second = 7, third = 11, fourth = 13)
    first + second + third + fourth

  -> with_five(first, second = 2, third = 3, fourth = 4, fifth = 5)
    first + second + third + fourth + fifth

+ OneArgDispatchBenchChild < OneArgDispatchBenchTarget
  -> child_only
    true

+ OneArgDispatchBenchOverride < OneArgDispatchBenchTarget
  -> echo(value)
    value + 1

-> call_generic(receiver, name, argument, iterations, slot)
  ccall("w_bench_one_arg_generic", receiver, name, argument, iterations, slot)

-> call_specialized(receiver, name, argument, iterations, slot)
  ccall("w_bench_one_arg_specialized", receiver, name, argument, iterations, slot)

-> timed_generic(receiver, name, argument, iterations, slot)
  started = clock()
  value = call_generic(receiver, name, argument, iterations, slot)
  [clock() - started, value]

-> timed_specialized(receiver, name, argument, iterations, slot)
  started = clock()
  value = call_specialized(receiver, name, argument, iterations, slot)
  [clock() - started, value]

-> run_single_pair(receiver, name, argument, iterations, slot, parity)
  if parity == 0
    generic = timed_generic(receiver, name, argument, iterations, slot)
    specialized = timed_specialized(receiver, name, argument, iterations, slot)
  else
    specialized = timed_specialized(receiver, name, argument, iterations, slot)
    generic = timed_generic(receiver, name, argument, iterations, slot)
  [generic, specialized]

-> run_pair(label, receiver, name, argument, expected, iterations, slot, parity, emit = true)
  first = run_single_pair(receiver, name, argument, iterations, slot, parity)
  second = run_single_pair(receiver, name, argument, iterations, slot, parity == 0 ? 1 : 0)
  generic_seconds = first[0][0] + second[0][0]
  specialized_seconds = first[1][0] + second[1][0]
  results_match = first[0][1] == expected && first[1][1] == expected
  results_match = results_match && second[0][1] == expected
  results_match = results_match && second[1][1] == expected
  if !results_match
    << "FAIL [label] result mismatch"
    exit(1)
  if emit
    calls = iterations * 2
    generic_ns = generic_seconds * 1_000_000_000 / calls
    specialized_ns = specialized_seconds * 1_000_000_000 / calls
    ratio = specialized_seconds / generic_seconds
    << "RESULT|[label]|[generic_ns]|[specialized_ns]|[ratio]|[expected]"

-> run_correctness(source_receiver, native_receiver)
  source_ok = call_generic(source_receiver, "echo", 91, 3, 0) == 91
  source_ok = source_ok && call_specialized(source_receiver, "echo", 91, 3, 0) == 91
  if !source_ok
    << "FAIL source arity-one correctness"
    exit(1)
  native_ok = call_generic(native_receiver, "get", 4, 3, 1) == 44
  native_ok = native_ok && call_specialized(native_receiver, "get", 4, 3, 1) == 44
  if !native_ok
    << "FAIL native arity-minus-one correctness"
    exit(1)

  # Generic dispatch ignores surplus arguments for a zero-arity source
  # method and pads a missing trailing source argument with nil, allowing the
  # callee's default expression to run.  Keep each method on its own cache
  # slot because compiler IC sites have a fixed method name.
  ignored_ok = call_generic(source_receiver, "no_args", 999, 2, 2) == 13
  ignored_ok = ignored_ok && call_specialized(source_receiver, "no_args", 999, 2, 2) == 13
  if !ignored_ok
    << "FAIL ignored extra argument correctness"
    exit(1)

  default_ok = call_generic(source_receiver, "with_default", 5, 2, 3) == 32
  default_ok = default_ok && call_specialized(source_receiver, "with_default", 5, 2, 3) == 32
  if !default_ok
    << "FAIL nil-filled trailing argument correctness"
    exit(1)

  arity_three_ok = call_generic(source_receiver, "with_three", 5, 2, 5) == 35
  arity_three_ok = arity_three_ok && call_specialized(source_receiver, "with_three", 5, 2, 5) == 35
  if !arity_three_ok
    << "FAIL arity-three nil-fill correctness"
    exit(1)

  arity_four_ok = call_generic(source_receiver, "with_four", 5, 2, 6) == 36
  arity_four_ok = arity_four_ok && call_specialized(source_receiver, "with_four", 5, 2, 6) == 36
  if !arity_four_ok
    << "FAIL arity-four nil-fill correctness"
    exit(1)

  # Arity five is intentionally outside both dispatchers' direct-call switch.
  # Repeating it proves that a populated-but-unsupported cache entry continues
  # through the shared slow path rather than calling an incompatible function.
  arity_five_ok = call_generic(source_receiver, "with_five", 1, 3, 7) == 15
  arity_five_ok = arity_five_ok && call_specialized(source_receiver, "with_five", 1, 3, 7) == 15
  if !arity_five_ok
    << "FAIL arity-five unsupported-cache fallback correctness"
    exit(1)

  child = OneArgDispatchBenchChild.new()
  override = OneArgDispatchBenchOverride.new()
  replacement_ok = call_generic(child, "echo", 40, 2, 4) == 40
  replacement_ok = replacement_ok && call_generic(override, "echo", 40, 2, 4) == 41
  replacement_ok = replacement_ok && call_generic(child, "echo", 40, 2, 4) == 40
  replacement_ok = replacement_ok && call_specialized(child, "echo", 40, 2, 4) == 40
  replacement_ok = replacement_ok && call_specialized(override, "echo", 40, 2, 4) == 41
  replacement_ok = replacement_ok && call_specialized(child, "echo", 40, 2, 4) == 40
  if !replacement_ok
    << "FAIL inherited/override cache replacement correctness"
    exit(1)

  # 40 + 42 bytes is above W_SLAB_SSO2_MAX (61), so these are real ropes.
  # The match crosses the concatenation boundary and exercises receiver
  # flattening before both dispatch-key calculation and native String lookup.
  rope_left = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMN"
  rope_right = "opqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123"
  generic_rope = ccall("w_str_concat", rope_left, rope_right)
  specialized_rope = ccall("w_str_concat", rope_left, rope_right)
  rope_ok = call_generic(generic_rope, "include?", "MNop", 2, 8) == true
  rope_ok = rope_ok && call_specialized(specialized_rope, "include?", "MNop", 2, 8) == true
  if !rope_ok
    << "FAIL rope flatten plus one-argument String native correctness"
    exit(1)

  # Reuse one cache slot and one method name across different native receiver
  # shapes. This checks Array/String key replacement in both directions after
  # the rope has already installed the String key in this slot.
  array_value = [11, 22, 33]
  string_value = "two-two"
  native_replacement_ok = call_generic(array_value, "include?", 22, 2, 8) == true
  native_replacement_ok = native_replacement_ok && call_generic(string_value, "include?", "two", 2, 8) == true
  native_replacement_ok = native_replacement_ok && call_generic(array_value, "include?", 22, 2, 8) == true
  native_replacement_ok = native_replacement_ok && call_specialized(array_value, "include?", 22, 2, 8) == true
  native_replacement_ok = native_replacement_ok && call_specialized(string_value, "include?", "two", 2, 8) == true
  native_replacement_ok = native_replacement_ok && call_specialized(array_value, "include?", 22, 2, 8) == true
  if !native_replacement_ok
    << "FAIL same-name Array/String native cache replacement correctness"
    exit(1)

  # Closure `call` is resolved by the special uncacheable slow path. Repeating
  # the call ensures neither dispatcher mistakes an empty cache for a hit.
  increment = -> (value)
    value + 1
  closure_ok = call_generic(increment, "call", 4, 3, 9) == 5
  closure_ok = closure_ok && call_specialized(increment, "call", 4, 3, 9) == 5
  if !closure_ok
    << "FAIL uncacheable closure-call correctness"
    exit(1)

  << "correctness: ok (source arities 0-5, native -1, rope flatten, slow fallbacks, inheritance, and cache replacement)"

args = argv()
mode = args.size() > 0 ? args[0] : "bench"
iterations = args.size() > 1 ? args[1].to_i : DEFAULT_ITERS
parity = args.size() > 2 ? args[2].to_i : 0
only = args.size() > 3 ? args[3] : ""

source_receiver = OneArgDispatchBenchTarget.new()
native_receiver = [0, 11, 22, 33, 44, 55, 66, 77]

if mode == "check"
  run_correctness(source_receiver, native_receiver)
  exit(0)

if iterations <= 0 || (parity != 0 && parity != 1)
  << "usage: one_arg_dispatch_ab bench POSITIVE_ITERS (0|1) [source1|native1]"
  exit(2)

if only == "" || only == "source1"
  run_pair("source1", source_receiver, "echo", 91, 91,
           WARMUP_ITERS, 0, parity, false)
if only == "" || only == "native1"
  run_pair("native1", native_receiver, "get", 4, 44,
           WARMUP_ITERS, 1, parity, false)

if only == "" || only == "source1"
  run_pair("source1", source_receiver, "echo", 91, 91,
           iterations, 0, parity)
if only == "" || only == "native1"
  run_pair("native1", native_receiver, "get", 4, 44,
           iterations, 1, parity)
