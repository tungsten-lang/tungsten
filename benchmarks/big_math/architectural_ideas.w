# Executable upper-bound experiments for architectural BigInt suggestions.
# Each lane is a full release/native/fast Tungsten program path. Setup is kept
# outside the timed interval and the printed checksum makes paired semantics
# observable to the runner.

use core/algebra/p_adic

-> report(lane, width, auxiliary, iterations, started_at, finished_at, checksum)
  ns = (finished_at - started_at) * ~1000000000.0 / iterations.to_f()
  << lane + "\t" + width.to_s() + "\t" + auxiliary.to_s() + "\t" + iterations.to_s() + "\t" + ns.to_s() + "\t" + checksum.to_s()

-> jit_chain(width, squares, iterations)
  bits = width * 64
  modulus = (1 << (bits - 1)) + (1 << (bits / 2)) + 159
  base = (1 << (bits - 2)) + 987654321
  sink = 0 ## i64
  outer = 0 ## i64
  t0 = clock()
  while outer < iterations
    value = base
    inner = 0 ## i64
    while inner < squares
      value *= value
      value %= modulus
      inner += 1
    sink = sink ^ (value & 65535)
    outer += 1
  t1 = clock()
  report("jit-chain", width, squares, iterations, t0, t1, sink)

-> jit_primitive(width, squares, iterations)
  bits = width * 64
  modulus = (1 << (bits - 1)) + (1 << (bits / 2)) + 159
  base = (1 << (bits - 2)) + 987654321
  exponent = 1 << squares
  sink = 0 ## i64
  outer = 0 ## i64
  t0 = clock()
  while outer < iterations
    value = base.modpow(exponent, modulus)
    sink = sink ^ (value & 65535)
    outer += 1
  t1 = clock()
  report("jit-primitive", width, squares, iterations, t0, t1, sink)

-> loop_serial(width, terms, iterations)
  bits = width * 64
  value = (1 << (bits - 1)) + 987654321
  sink = 0 ## i64
  outer = 0 ## i64
  t0 = clock()
  while outer < iterations
    accumulator = 0 ## big
    index = 0 ## i64
    while index < terms
      accumulator += value * ((index & 7) + 1)
      index += 1
    sink = sink ^ (accumulator & 65535)
    outer += 1
  t1 = clock()
  report("loop-serial", width, terms, iterations, t0, t1, sink)

-> loop_four(width, terms, iterations)
  bits = width * 64
  value = (1 << (bits - 1)) + 987654321
  sink = 0 ## i64
  outer = 0 ## i64
  t0 = clock()
  while outer < iterations
    a0 = 0 ## big
    a1 = 0 ## big
    a2 = 0 ## big
    a3 = 0 ## big
    index = 0 ## i64
    while index < terms
      a0 += value * ((index & 7) + 1)
      a1 += value * (((index + 1) & 7) + 1)
      a2 += value * (((index + 2) & 7) + 1)
      a3 += value * (((index + 3) & 7) + 1)
      index += 4
    accumulator = a0 + a1 + a2 + a3
    sink = sink ^ (accumulator & 65535)
    outer += 1
  t1 = clock()
  report("loop-four", width, terms, iterations, t0, t1, sink)

-> fixed_decimal(iterations)
  balance = 12345.67
  increment = 0.01
  index = 0 ## i64
  t0 = clock()
  while index < iterations
    balance += increment
    index += 1
  t1 = clock()
  checksum = (balance * 100).to_i()
  report("fixed-decimal", 2, 10, iterations, t0, t1, checksum)

-> fixed_scaled(iterations)
  cents = 1234567 ## i64
  index = 0 ## i64
  t0 = clock()
  while index < iterations
    cents += 1
    index += 1
  t1 = clock()
  report("fixed-scaled", 2, 10, iterations, t0, t1, cents)

-> padic_generic(width, exponent, iterations)
  precision = width * 40
  modulus = 3 ** precision
  base = (1 << (width * 63 - 2)) + 1234567
  sink = 0 ## i64
  index = 0 ## i64
  t0 = clock()
  while index < iterations
    value = PadicArithmetic.power_mod(base, exponent, modulus)
    sink = sink ^ (value & 65535)
    index += 1
  t1 = clock()
  report("padic-generic", width, exponent, iterations, t0, t1, sink)

-> padic_primitive(width, exponent, iterations)
  precision = width * 40
  modulus = 3 ** precision
  base = (1 << (width * 63 - 2)) + 1234567
  sink = 0 ## i64
  index = 0 ## i64
  t0 = clock()
  while index < iterations
    value = base.modpow(exponent, modulus)
    sink = sink ^ (value & 65535)
    index += 1
  t1 = clock()
  report("padic-primitive", width, exponent, iterations, t0, t1, sink)

args = argv()
lane = args[0]
width = args[1].to_i()
auxiliary = args[2].to_i()
iterations = args[3].to_i()
if lane == "jit-chain"
  jit_chain(width, auxiliary, iterations)
elsif lane == "jit-primitive"
  jit_primitive(width, auxiliary, iterations)
elsif lane == "loop-serial"
  loop_serial(width, auxiliary, iterations)
elsif lane == "loop-four"
  loop_four(width, auxiliary, iterations)
elsif lane == "fixed-decimal"
  fixed_decimal(iterations)
elsif lane == "fixed-scaled"
  fixed_scaled(iterations)
elsif lane == "padic-generic"
  padic_generic(width, auxiliary, iterations)
else
  padic_primitive(width, auxiliary, iterations)
