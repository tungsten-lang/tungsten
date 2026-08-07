# BigInt#prime? — served by the source shim over the runtime's
# screen / Mersenne Lucas-Lehmer / Proth / BPSW policy. Pins known
# primes and composites across widths and the specialized fast paths,
# on both engines.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# Screen: negatives, 0, 1 are never prime
check("screen.negative", (0 - (10 ** 40)).prime?, false)
check("screen.zero_heap", ((10 ** 40) * 0).prime?, false)

# One-limb heap BigInts (2^47..2^64): deterministic u64 test
m61 = 2 ** 61 - 1
check("one_limb.mersenne61", m61.prime?, true)
check("one_limb.composite", (m61 - 2).prime?, false)
check("one_limb.square", (2147483647 * 2147483647).prime?, false)

# Mersenne fast path: exact Lucas-Lehmer proof
check("mersenne.m89", (2 ** 89 - 1).prime?, true)
check("mersenne.m107", (2 ** 107 - 1).prime?, true)
check("mersenne.m127", (2 ** 127 - 1).prime?, true)
check("mersenne.m101_composite", (2 ** 101 - 1).prime?, false)

# Generic BPSW on multi-limb values
p255 = 2 ** 255 - 19
check("bpsw.ed25519_prime", p255.prime?, true)
check("bpsw.even", (p255 + 1).prime?, false)
check("bpsw.semiprime", ((2 ** 61 - 1) * (2 ** 89 - 1)).prime?, false)
check("bpsw.small_factor", (p255 * 3).prime?, false)

<< "bigint_prime_spec: all checks passed"
