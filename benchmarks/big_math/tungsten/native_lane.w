# Source-language Tungsten lane for `bin/tungsten bench bignum`.
#
# Operand construction, timing, and the one-shot C oracle are benchmark
# support ccalls. Timed arithmetic, bitwise, shift, comparison, sign, power,
# and conversion bodies are ordinary compiled Tungsten source; gcd, lcm, and
# isqrt deliberately call their retained C kernel boundaries directly. The
# executable closes the Core and method-table world after all definitions so
# direct dispatch is both sound and representative of a deliberately locked
# production program.

MAX_ITERATIONS = 40_000_000
PILOT_MIN_NS = 20_000
WARM_NS = 500_000
SHIFT_BITS = 13
POW_EXPONENT = 5

-> source_operand(operation, limbs, which)
  ccall("w_bench_tungsten_source_operand", operation, limbs, which)

-> thread_cpu_ns
  ccall("w_bench_tungsten_source_thread_cpu_ns")

-> release_value(value)
  ccall("w_bench_tungsten_source_release", value)

-> source_reference(operation, a, b, modulus, decimal)
  ccall("w_bench_tungsten_source_reference", operation, a, b, modulus, decimal)

-> assert_source_equal(operation, got, expected)
  ccall("w_bench_tungsten_source_assert_equal", operation, got, expected)

-> finish_sample(started, iterations, result, checksum)
  elapsed = thread_cpu_ns() - started
  release_value(result)
  [elapsed, checksum, iterations]

-> time_add(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a + b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_sub(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a - b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_mul(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a * b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_sqr(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a * a
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_div(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a / b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_mod(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a % b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_gcd(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_gcd", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_and(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a & b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_or(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a | b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_xor(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a ^ b
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_shl(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a << SHIFT_BITS
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_shr(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a >> SHIFT_BITS
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_cmp(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a <=> b
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_neg(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = -a
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_abs(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a.abs
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_pow(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a ** POW_EXPONENT
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_powmod(a, b, modulus, iterations)(BigInt BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = a.pow(b, modulus)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_lcm(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_lcm", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_isqrt(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("bigint_isqrt_any", a)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_tostr(a, iterations)(BigInt i64)
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    text = a.to_s()
    checksum += (wvalue_bits(text) & 255) + i
    release_value(text)
    i += 1
  [thread_cpu_ns() - started, checksum, iterations]

-> time_fromstr(decimal, iterations)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = decimal.to_i
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> measure(operation, a, b, modulus, decimal, iterations)
  if operation == "add" || operation == "add1"
    return time_add(a, b, iterations)
  if operation == "sub" || operation == "sub1"
    return time_sub(a, b, iterations)
  if operation == "mul" || operation == "mul1"
    return time_mul(a, b, iterations)
  if operation == "sqr"
    return time_sqr(a, iterations)
  if operation == "div" || operation == "div1"
    return time_div(a, b, iterations)
  if operation == "mod"
    return time_mod(a, b, iterations)
  if operation == "gcd"
    return time_gcd(a, b, iterations)
  if operation == "and"
    return time_and(a, b, iterations)
  if operation == "or"
    return time_or(a, b, iterations)
  if operation == "xor"
    return time_xor(a, b, iterations)
  if operation == "shl"
    return time_shl(a, iterations)
  if operation == "shr"
    return time_shr(a, iterations)
  if operation == "cmp"
    return time_cmp(a, b, iterations)
  if operation == "neg"
    return time_neg(a, iterations)
  if operation == "abs"
    return time_abs(a, iterations)
  if operation == "pow"
    return time_pow(a, iterations)
  if operation == "powmod"
    return time_powmod(a, b, modulus, iterations)
  if operation == "lcm"
    return time_lcm(a, b, iterations)
  if operation == "isqrt"
    return time_isqrt(a, iterations)
  if operation == "tostr"
    return time_tostr(a, iterations)
  if operation == "fromstr"
    return time_fromstr(decimal, iterations)
  raise "unknown bignum benchmark operation: " + operation

-> warm_chunk(operation, limbs)
  if operation == "powmod"
    return 1
  if operation == "isqrt" && limbs >= 4
    return 1
  if operation == "lcm" && limbs >= 16
    return 1
  if operation in ("div" "mod" "gcd") && limbs >= 128
    return 1
  if operation in ("mul" "sqr") && limbs >= 256
    return 8
  if operation in ("pow" "tostr" "fromstr") && limbs >= 64
    return 8
  1024

-> warmed_sample(operation, a, b, modulus, decimal, limbs, iterations)
  chunk = warm_chunk(operation, limbs)
  warm_started = thread_cpu_ns()
  while thread_cpu_ns() - warm_started < WARM_NS
    measure(operation, a, b, modulus, decimal, chunk)
  sample = measure(operation, a, b, modulus, decimal, iterations)
  sample[0].to_f() / iterations.to_f()

-> calibrate(operation, a, b, modulus, decimal, limbs, target_ns)
  pilot = 1
  while true
    per_operation = warmed_sample(operation, a, b, modulus, decimal, limbs, pilot)
    elapsed = per_operation * pilot.to_f()
    if elapsed >= PILOT_MIN_NS || pilot >= 4096
      estimate = (target_ns / per_operation).to_i()
      return 1 if estimate < 1
      return MAX_ITERATIONS if estimate > MAX_ITERATIONS
      return estimate
    pilot *= 16

-> apply_once(operation, a, b, modulus, decimal)
  return a + b if operation == "add" || operation == "add1"
  return a - b if operation == "sub" || operation == "sub1"
  return a * b if operation == "mul" || operation == "mul1"
  return a * a if operation == "sqr"
  return a / b if operation == "div" || operation == "div1"
  return a % b if operation == "mod"
  return ccall("w_bigint_gcd", a, b) if operation == "gcd"
  return a & b if operation == "and"
  return a | b if operation == "or"
  return a ^ b if operation == "xor"
  return a << SHIFT_BITS if operation == "shl"
  return a >> SHIFT_BITS if operation == "shr"
  return a <=> b if operation == "cmp"
  return -a if operation == "neg"
  return a.abs if operation == "abs"
  return a ** POW_EXPONENT if operation == "pow"
  return a.pow(b, modulus) if operation == "powmod"
  return ccall("w_bigint_lcm", a, b) if operation == "lcm"
  return ccall("bigint_isqrt_any", a) if operation == "isqrt"
  return a.to_s() if operation == "tostr"
  return decimal.to_i if operation == "fromstr"
  raise "unknown bignum benchmark operation: " + operation

-> build_operands(operation, limbs)
  a = source_operand(operation, limbs, 0)
  b = source_operand(operation, limbs, 1)
  modulus = source_operand(operation, limbs, 2)
  decimal = operation == "fromstr" ? a.to_s() : ""
  [a, b, modulus, decimal]

-> run_self_test
  operations = [
    "add", "sub", "mul", "sqr", "div", "mod", "gcd", "and", "or",
    "xor", "shl", "shr", "cmp", "neg", "abs", "pow", "powmod", "lcm",
    "isqrt", "tostr", "fromstr", "add1", "sub1", "mul1", "div1"
  ]
  i = 0
  while i < operations.size
    operation = operations[i]
    values = build_operands(operation, 2)
    got = apply_once(operation, values[0], values[1], values[2], values[3])
    expected = source_reference(
      operation, values[0], values[1], values[2], values[3]
    )
    assert_source_equal(operation, got, expected)
    release_value(got)
    release_value(expected)
    i += 1
  << "compiled Tungsten bignum source lane: self-test passed"

-> run_sweep(operation, limbs, runs, target_ms)
  if limbs < 1 || limbs > 1_048_576 || runs < 1 || target_ms <= 0
    raise "invalid --sweep arguments"
  values = build_operands(operation, limbs)
  a = values[0]
  b = values[1]
  modulus = values[2]
  decimal = values[3]
  got = apply_once(operation, a, b, modulus, decimal)
  expected = source_reference(operation, a, b, modulus, decimal)
  assert_source_equal(operation, got, expected)
  release_value(got)
  release_value(expected)

  target_ns = target_ms * 1_000_000.0
  iterations = calibrate(
    operation, a, b, modulus, decimal, limbs, target_ns
  )
  best = nil
  run = 0
  while run < runs
    sample = warmed_sample(
      operation, a, b, modulus, decimal, limbs, iterations
    )
    if best == nil || sample < best
      best = sample
    run += 1
  << "external\ttungsten_source\t" + operation + "\t" + limbs.to_s() + "\t" + iterations.to_s() + "\t" + best.to_s()

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
if args.size == 1 && args[0] == "--self-test"
  run_self_test()
  exit(0)
if args.size != 5 || args[0] != "--sweep"
  << "usage: bench_big_math_tungsten_source --self-test | --sweep OP LIMBS RUNS TARGET_MS"
  exit(2)
run_sweep(args[1], args[2].to_i, args[3].to_i, args[4].to_f)
