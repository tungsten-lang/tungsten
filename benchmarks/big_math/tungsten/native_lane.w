# Tungsten native lane for `bin/tungsten bench bignum`.
#
# Operand construction, timing, and the one-shot C oracle are benchmark
# support ccalls. Timed arithmetic, bitwise, shift, comparison, sign, power,
# and conversion bodies are ordinary native-compiled Tungsten; gcd and lcm
# deliberately call their retained C kernel boundaries directly. Integer
# square root uses BigInt#isqrt's stable source seam, whose one- and two-limb
# leaves are native and whose wider divide-and-conquer path retains the C
# kernel boundary. The
# executable closes the Core and method-table world after all definitions so
# direct dispatch is both sound and representative of a deliberately locked
# production program.

MAX_ITERATIONS = 40_000_000
PILOT_MIN_NS = 20_000
WARM_NS = 500_000
SHIFT_BITS = 13
POW_EXPONENT = 5

-> native_operand(operation, limbs, which)
  ccall("w_bench_tungsten_native_operand", operation, limbs, which)

-> thread_cpu_ns
  ccall("w_bench_tungsten_native_thread_cpu_ns")

-> release_value(value)
  ccall("w_bench_tungsten_native_release", value)

# The add/add1 result type and this benchmark fixture's subtraction,
# multiplication, and square results are statically boxed. Every multiply
# operand has its top bit set, so even the smallest 1x1 product is at least
# 2^126 and cannot demote to i48. Match the direct C lane's alias-aware BigInt
# handoff without crossing the general w_value_free heap-kind dispatcher.
# (The subtraction fixtures retain at least one full-width magnitude limb;
# focused correctness specs cover the source leaf's inline-result cases
# separately.)
-> release_bigint_value(value)
  ccall_nobox("w_bigint_release_dead_raw", value)

-> native_reference(operation, a, b, modulus, decimal)
  ccall("w_bench_tungsten_native_reference", operation, a, b, modulus, decimal)

-> assert_native_equal(operation, got, expected)
  ccall("w_bench_tungsten_native_assert_equal", operation, got, expected)

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
    release_bigint_value(result)
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
    release_bigint_value(result)
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
    release_bigint_value(result)
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
    release_bigint_value(result)
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

# Compare is pure: the compiled `<=>` route is a magnitude compare the
# optimizer would hoist out of the timing loop (it did, once the route no
# longer went through an opaque call). Launder both operands through an
# empty asm barrier every iteration, exactly as the C lane does, so each
# iteration performs one compare.
fn __bench_launder(x) (i64) i64
  ll <<~IR
    entry:
      %r = call i64 asm sideeffect "", "=r,0"(i64 %x)
      ret i64 %r
  IR

-> time_cmp(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = la <=> lb
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
    next_result = ccall("__w_bigint_isqrt_src", a)
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

-> time_fromstr(decimal, iterations)(String i64)
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

-> time_not(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_not", a)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_tdiv(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_tdiv", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_tmod(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_tmod", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_cdiv(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_cdiv", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_cmod(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_cmod", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_divexact(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_divexact", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_divisible(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = ccall("w_bigint_divisible_p", la, lb)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_iroot(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_iroot", a, 3)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_psquare(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_perfect_square_p", la)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_invmod(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_invmod", a, b)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_jacobi(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = ccall("w_bigint_jacobi", la, lb)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_kronecker(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = ccall("w_bigint_kronecker", la, lb)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_bitlen(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_bit_length", la)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_popcnt(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_popcount", la)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_hamdist(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = ccall("w_bigint_hamdist", la, lb)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_scan1(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_scan1", la, 0)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_scan0(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_scan0", la, 0)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_tstbit(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    next_result = ccall("w_bigint_tstbit", la, SHIFT_BITS)
    checksum += (wvalue_bits(next_result) & 255) + i
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_setbit(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_setbit", a, SHIFT_BITS)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_clrbit(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_clrbit", a, 0)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_combit(a, iterations)(BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    next_result = ccall("w_bigint_combit", a, SHIFT_BITS)
    checksum += (wvalue_bits(next_result) & 255) + i
    release_value(result)
    result = next_result
    i += 1
  finish_sample(started, iterations, result, checksum)

-> time_cmpabs(a, b, iterations)(BigInt BigInt i64)
  result = nil
  checksum = 0 ## i64
  i = 0 ## i64
  started = thread_cpu_ns()
  while i < iterations
    la = wvalue_from_bits(__bench_launder(wvalue_bits(a))) ## big
    lb = wvalue_from_bits(__bench_launder(wvalue_bits(b))) ## big
    next_result = ccall("w_bigint_cmpabs", la, lb)
    checksum += (wvalue_bits(next_result) & 255) + i
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
  if operation == "mod" || operation == "mod1"
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
  if operation == "not"
    return time_not(a, iterations)
  if operation == "tdiv"
    return time_tdiv(a, b, iterations)
  if operation == "tmod"
    return time_tmod(a, b, iterations)
  if operation == "cdiv"
    return time_cdiv(a, b, iterations)
  if operation == "cmod"
    return time_cmod(a, b, iterations)
  if operation == "divexact"
    return time_divexact(a, b, iterations)
  if operation == "divisible"
    return time_divisible(a, b, iterations)
  if operation == "iroot"
    return time_iroot(a, iterations)
  if operation == "psquare"
    return time_psquare(a, iterations)
  if operation == "invmod"
    return time_invmod(a, b, iterations)
  if operation == "jacobi"
    return time_jacobi(a, b, iterations)
  if operation == "kronecker"
    return time_kronecker(a, b, iterations)
  if operation == "bitlen"
    return time_bitlen(a, iterations)
  if operation == "popcnt"
    return time_popcnt(a, iterations)
  if operation == "hamdist"
    return time_hamdist(a, b, iterations)
  if operation == "scan1"
    return time_scan1(a, iterations)
  if operation == "scan0"
    return time_scan0(a, iterations)
  if operation == "tstbit"
    return time_tstbit(a, iterations)
  if operation == "setbit"
    return time_setbit(a, iterations)
  if operation == "clrbit"
    return time_clrbit(a, iterations)
  if operation == "combit"
    return time_combit(a, iterations)
  if operation == "cmpabs"
    return time_cmpabs(a, b, iterations)
  raise "unknown bignum benchmark operation: " + operation

-> warm_chunk(operation, limbs)
  if operation in ("powmod" "invmod" "iroot")
    return 1
  if operation in ("isqrt" "psquare" "jacobi" "kronecker") && limbs >= 4
    return 1
  if operation == "lcm" && limbs >= 16
    return 1
  if operation in ("div" "mod" "tdiv" "tmod" "cdiv" "cmod" "divexact" "divisible" "gcd") && limbs >= 128
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
  return a % b if operation == "mod" || operation == "mod1"
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
  return ccall("__w_bigint_isqrt_src", a) if operation == "isqrt"
  return a.to_s() if operation == "tostr"
  return decimal.to_i if operation == "fromstr"
  return ccall("w_bigint_not", a) if operation == "not"
  return ccall("w_bigint_tdiv", a, b) if operation == "tdiv"
  return ccall("w_bigint_tmod", a, b) if operation == "tmod"
  return ccall("w_bigint_cdiv", a, b) if operation == "cdiv"
  return ccall("w_bigint_cmod", a, b) if operation == "cmod"
  return ccall("w_bigint_divexact", a, b) if operation == "divexact"
  return ccall("w_bigint_divisible_p", a, b) if operation == "divisible"
  return ccall("w_bigint_iroot", a, 3) if operation == "iroot"
  return ccall("w_bigint_perfect_square_p", a) if operation == "psquare"
  return ccall("w_bigint_invmod", a, b) if operation == "invmod"
  return ccall("w_bigint_jacobi", a, b) if operation == "jacobi"
  return ccall("w_bigint_kronecker", a, b) if operation == "kronecker"
  return ccall("w_bigint_bit_length", a) if operation == "bitlen"
  return ccall("w_bigint_popcount", a) if operation == "popcnt"
  return ccall("w_bigint_hamdist", a, b) if operation == "hamdist"
  return ccall("w_bigint_scan1", a, 0) if operation == "scan1"
  return ccall("w_bigint_scan0", a, 0) if operation == "scan0"
  return ccall("w_bigint_tstbit", a, SHIFT_BITS) if operation == "tstbit"
  return ccall("w_bigint_setbit", a, SHIFT_BITS) if operation == "setbit"
  return ccall("w_bigint_clrbit", a, 0) if operation == "clrbit"
  return ccall("w_bigint_combit", a, SHIFT_BITS) if operation == "combit"
  return ccall("w_bigint_cmpabs", a, b) if operation == "cmpabs"
  raise "unknown bignum benchmark operation: " + operation

-> build_operands(operation, limbs)
  a = native_operand(operation, limbs, 0)
  b = native_operand(operation, limbs, 1)
  modulus = native_operand(operation, limbs, 2)
  decimal = operation == "fromstr" ? a.to_s() : ""
  [a, b, modulus, decimal]

-> run_self_test
  operations = [
    "add", "sub", "mul", "sqr", "div", "mod", "gcd", "and", "or",
    "xor", "shl", "shr", "cmp", "neg", "abs", "pow", "powmod", "lcm",
    "isqrt", "tostr", "fromstr", "add1", "sub1", "mul1", "div1",
    "mod1", "not", "tdiv", "tmod", "cdiv", "cmod", "divexact",
    "divisible", "iroot", "psquare", "invmod", "jacobi", "kronecker",
    "bitlen", "popcnt", "hamdist", "scan1", "scan0", "tstbit",
    "setbit", "clrbit", "combit", "cmpabs"
  ]
  i = 0
  while i < operations.size
    operation = operations[i]
    values = build_operands(operation, 2)
    got = apply_once(operation, values[0], values[1], values[2], values[3])
    expected = native_reference(
      operation, values[0], values[1], values[2], values[3]
    )
    assert_native_equal(operation, got, expected)
    release_value(got)
    release_value(expected)
    i += 1

  # These are the first widths admitted by the source allocation/funnel
  # paths. Keep their raw allocator ABI crossings covered rather than testing
  # only the small-width C fallbacks above.
  shift_operations = ["shl", "shr"]
  shift_limbs = [65, 33]
  i = 0
  while i < shift_operations.size
    operation = shift_operations[i]
    values = build_operands(operation, shift_limbs[i])
    got = apply_once(operation, values[0], values[1], values[2], values[3])
    expected = native_reference(
      operation, values[0], values[1], values[2], values[3]
    )
    assert_native_equal(operation, got, expected)
    release_value(got)
    release_value(expected)
    i += 1
  << "Tungsten native bignum lane: self-test passed"

# Operands for one timed cell, checked once against the C oracle before any
# timing so a wrong answer can never be reported as a fast one.
-> build_checked_operands(operation, limbs)
  values = build_operands(operation, limbs)
  got = apply_once(operation, values[0], values[1], values[2], values[3])
  expected = native_reference(
    operation, values[0], values[1], values[2], values[3]
  )
  assert_native_equal(operation, got, expected)
  release_value(got)
  release_value(expected)
  values

-> run_sweep(operation, limbs, runs, target_ms)
  if limbs < 1 || limbs > 1_048_576 || runs < 1 || target_ms <= 0
    raise "invalid --sweep arguments"
  values = build_checked_operands(operation, limbs)
  a = values[0]
  b = values[1]
  modulus = values[2]
  decimal = values[3]

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
  << "external\ttungsten_native\t" + operation + "\t" + limbs.to_s() + "\t" + iterations.to_s() + "\t" + best.to_s()

# One warmed timed block of exactly ITERATIONS operations, run once.  The
# driver pairs these single-block processes against the C harness's
# `--bench-boxed-block` in ABBA quartets, so the process is calibrated by
# its caller and reports the one sample it took: no pilot, no min-of-runs.
-> run_block(operation, limbs, iterations)
  if limbs < 1 || limbs > 1_048_576 || iterations < 1 || iterations > MAX_ITERATIONS
    raise "invalid --block arguments"
  values = build_checked_operands(operation, limbs)
  sample = warmed_sample(
    operation, values[0], values[1], values[2], values[3], limbs, iterations
  )
  << "block\ttungsten_native\t" + operation + "\t" + limbs.to_s() + "\t" + iterations.to_s() + "\t" + sample.to_s()

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

args = argv()
if args.size == 1 && args[0] == "--self-test"
  run_self_test()
  exit(0)
if args.size == 4 && args[0] == "--block"
  run_block(args[1], args[2].to_i, args[3].to_i)
  exit(0)
if args.size != 5 || args[0] != "--sweep"
  << "usage: bench_big_math_tungsten_native --self-test | --sweep OP LIMBS RUNS TARGET_MS | --block OP LIMBS ITERATIONS"
  exit(2)
run_sweep(args[1], args[2].to_i, args[3].to_i, args[4].to_f)
