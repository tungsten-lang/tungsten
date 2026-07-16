# Public-dispatch production gate for Float#to_f and BigInt#to_i.
#
# This file deliberately has no `use` directive. The baseline reaches the two
# native IC handlers; the candidate must autoload the source classes and reach
# their public `self` bodies. Both roots compile this exact shared copy.

FLOAT_CASES = 22
BIGINT_CASES = 26
CORPUS_SIZE = 16
CORPUS_MASK = CORPUS_SIZE - 1
DEFAULT_ITERS = 40_000_000
DEFAULT_WARMUP = 1_000_000

-> float_case(index)
  ccall("w_identity_float_case", index)

-> float_value?(value)
  ccall("w_identity_float_p", value)

-> bigint_case(index)
  ccall("w_identity_bigint_case", index)

-> bigint_value?(value)
  ccall("w_identity_bigint_p", value)

-> bigint_size(value)
  ccall("w_identity_bigint_size", value)

-> bigint_capacity(value)
  ccall("w_identity_bigint_capacity", value)

-> fail_check(kind, index, path, got, expected)
  << "FAIL [kind] case=[index] [path] got=[got] expected=[expected]"
  exit(1)

-> check_bits(kind, index, path, got, expected)
  got_bits = wvalue_bits(got)
  expected_bits = wvalue_bits(expected)
  if got_bits != expected_bits
    fail_check(kind, index, path, got_bits, expected_bits)

-> check_float_identity
  i = 0
  while i < FLOAT_CASES
    value = float_case(i)
    if !float_value?(value)
      fail_check("Float#to_f", i, "factory type", false, true)
    check_bits("Float#to_f", i, "plain identity", value.to_f, value)
    check_bits("Float#to_f", i, "one surplus arg", value.to_f(17), value)
    check_bits("Float#to_f", i, "three surplus args", value.to_f(1, 2, 3), value)
    i += 1

-> check_bigint_identity
  expected_sizes = [0, 1, 1, -1, -1, 1, 1, -1, 1, -1,
                    2, 2, -2, -2, 2, -2, 3, -3, 3, -3,
                    3, -3, 4, -4, 4, -4]
  expected_caps = [1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
                   2, 2, 2, 2, 2, 2, 3, 3, 4, 4,
                   3, 3, 4, 4, 4, 4]
  i = 0
  while i < BIGINT_CASES
    value = bigint_case(i)
    if !bigint_value?(value)
      fail_check("BigInt#to_i", i, "factory type", false, true)
    if bigint_size(value) != expected_sizes[i]
      fail_check("BigInt#to_i", i, "signed limb count", bigint_size(value), expected_sizes[i])
    if bigint_capacity(value) != expected_caps[i]
      fail_check("BigInt#to_i", i, "capacity", bigint_capacity(value), expected_caps[i])
    check_bits("BigInt#to_i", i, "plain receiver identity", value.to_i, value)
    check_bits("BigInt#to_i", i, "one surplus arg", value.to_i(17), value)
    check_bits("BigInt#to_i", i, "three surplus args", value.to_i(1, 2, 3), value)
    i += 1

-> check
  check_float_identity()
  check_bigint_identity()
  << "PASS identity leaves: 22 Float encodings and 26 BigInt layouts; receiver identity and surplus args exact"

-> float_corpus(kind)
  indexes = nil
  if kind == "float-finite"
    indexes = [0, 1, 2, 3, 4, 5, 6, 7,
               8, 9, 10, 11, 20, 21, 0, 11]
  elsif kind == "float-nan"
    indexes = [12, 13, 14, 15, 18, 19, 12, 14,
               13, 15, 18, 19, 12, 19, 14, 18]
  else
    << "unknown Float stratum: [kind]"
    exit(2)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(float_case(indexes[i]))
    i += 1
  values

-> bigint_corpus(kind)
  indexes = nil
  if kind == "bigint-one-limb"
    indexes = [0, 1, 2, 3, 4, 5, 6, 7,
               8, 9, 1, 3, 5, 7, 8, 9]
  elsif kind == "bigint-multilimb"
    indexes = [10, 11, 12, 13, 14, 15, 16, 17,
               18, 19, 20, 21, 22, 23, 24, 25]
  else
    << "unknown BigInt stratum: [kind]"
    exit(2)
  values = []
  i = 0
  while i < CORPUS_SIZE
    values.push(bigint_case(indexes[i]))
    i += 1
  values

-> time_float(values, iters, run_id)
  checksum = 0
  i = 0
  # Keep the clock ccalls inside this three-argument function. Unknown ccall
  # wrappers are currently classified as pure, and <=2-argument pure
  # functions are memoized. Three arguments force this timing body to execute
  # on every call; run_id also makes the warmup/measurement distinction
  # explicit even though the C clock itself takes no arguments.
  start_ns = ccall("w_identity_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    result_bits = wvalue_bits(value.to_f)
    checksum += result_bits == wvalue_bits(value) ? 1 : 0
    i += 1
  [ccall("w_identity_thread_cpu_ns") - start_ns, checksum]

-> time_bigint(values, iters, run_id)
  checksum = 0
  i = 0
  start_ns = ccall("w_identity_thread_cpu_ns")
  while i < iters
    value = values[i & CORPUS_MASK]
    # Consume to_i directly through the raw-bit bridge. Assigning its boxed
    # heap-BigInt result first inherits an integer type fact and incorrectly
    # nan-unboxes the pointer before the checksum sees it.
    result_bits = wvalue_bits(value.to_i)
    checksum += result_bits == wvalue_bits(value) ? 1 : 0
    i += 1
  [ccall("w_identity_thread_cpu_ns") - start_ns, checksum]

-> run_once(kind, values, iters, run_id)
  if kind in ("float-finite" "float-nan")
    time_float(values, iters, run_id)
  else
    time_bigint(values, iters, run_id)

-> fatal_float_block
  value = float_case(8)
  hits = 0
  value.to_f -> (ignored)
    hits += 1
  << "FAIL Float#to_f trailing block unexpectedly returned; hits=[hits]"
  exit(9)

-> run_bigint_block_statement(value, counter)
  # Keep this call in statement position and make the helper's result
  # explicit. Binding the call's implicit-each result exposes a separate
  # lowering bug: to_i's integer type fact tries to unbox the correct nil.
  value.to_i -> (ignored)
    counter[0] += 1
    # Heap-BigInt result-each currently nan-unboxes the pointer as its count.
    # Break on entry so this real-syntax parity gate cannot run billions of
    # pointer-derived iterations while that pre-existing bug remains.
    break
  137

-> check_bigint_block
  # A deliberately noncanonical heap BigInt containing 2 exercises public
  # BigInt dispatch without conflating identity with normalization.
  value = bigint_case(26)
  check_bits("BigInt#to_i", 26, "block sentinel no-block identity", value.to_i, value)
  counter = [0]
  sentinel = run_bigint_block_statement(value, counter)
  if sentinel != 137
    fail_check("BigInt#to_i", 26, "trailing-block helper sentinel", sentinel, 137)
  if counter[0] != 1
    fail_check("BigInt#to_i", 26, "bounded statement-block hits", counter[0], 1)
  << "PASS BigInt#to_i native statement block: fixed sentinel, receiver identity, one bounded hit"

args = argv()
mode = args.size() > 0 ? args[0] : "check"
if mode == "check"
  check()
  exit(0)
if mode == "fatal-float-block"
  fatal_float_block()
  exit(9)
if mode == "check-bigint-block"
  check_bigint_block()
  exit(0)
if mode != "bench" || args.size() < 3
  << "usage: identity-leaf-public bench KIND ITERS [WARMUP]"
  exit(2)

kind = args[1]
iters = args[2].to_i
warmup = args.size() > 3 ? args[3].to_i : DEFAULT_WARMUP
values = nil
if kind in ("float-finite" "float-nan")
  values = float_corpus(kind)
else
  values = bigint_corpus(kind)
run_once(kind, values, warmup, 0)
result = run_once(kind, values, iters, 1)
<< "RESULT|[kind]|[result[0]]|[result[1]]"
