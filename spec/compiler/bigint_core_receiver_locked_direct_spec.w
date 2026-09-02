# Under LOCK_THE_DOORS! a receiver whose declared type is BigInt takes a
# tag-guarded direct call to the compiled Core method the runtime's superclass
# walk selects (BigInt -> Int -> Integer -> Real); `<=>` on two guard-proven
# BigInts collapses to w_spaceship. The slot may hold a demoted inline int,
# nil, or a program reopen, and every one of those must still see ordinary
# dispatch semantics.

+ BigInt
  -> reopened_probe
    "reopened:" + self.to_s()

  # A program reopen of an inherited selector must win over Core's Int#pow.
  -> pow(exp, modulus)
    if exp == 0 && modulus == 1
      return -7
    ccall("bigint_powmod_any", self, exp, modulus)

-> cmp3(a, b)(BigInt BigInt)
  a <=> b

-> cmp_mixed(a, b)(BigInt Int)
  a <=> b

-> abs_of(a)(BigInt)
  a.abs

-> tos(a)(BigInt)
  a.to_s()

-> tos_base(a)(BigInt)
  a.to_s(16)

-> powm(a, e, m)(BigInt BigInt BigInt)
  a.pow(e, m)

-> root(a)(BigInt)
  a.isqrt

-> probe(a)(BigInt)
  a.reopened_probe

-> demoted(a)(BigInt)
  # Shrinks below i48 at runtime: the typed slot now holds an inline int,
  # so every guarded site must take its slow arm.
  small = a - a + 5 ## big
  [small <=> 5, small.abs, small.to_s(), (0 - small).abs]

-> check(name, got, want)
  if got != want
    << "FAIL " + name + ": got " + got.to_s() + " want " + want.to_s()
    return 1
  0

Tungsten.LOCK_THE_DOORS!

failures = 0

big = (1 << 200) + 12345
bigger = (1 << 200) + 12346
neg = 0 - big

failures = failures + check("cmp.lt", cmp3(big, bigger), -1)
failures = failures + check("cmp.gt", cmp3(bigger, big), 1)
failures = failures + check("cmp.eq", cmp3(big, (1 << 200) + 12345), 0)
failures = failures + check("cmp.neg", cmp3(neg, big), -1)
failures = failures + check("cmp.mixed_int", cmp_mixed(big, 7), 1)
failures = failures + check("abs.positive_alias", abs_of(big) == big, true)
failures = failures + check("abs.negative", abs_of(neg) == big, true)
failures = failures + check("abs.negative_value", abs_of(neg).to_s(), big.to_s())
failures = failures + check("tos.decimal", tos(big), big.to_s())
failures = failures + check("tos.matches_untyped", tos(neg), neg.to_s())
failures = failures + check("tos.base16", tos_base(big), big.to_s(16))
failures = failures + check("powm.core_path", powm(big, 65537 + (1 << 70), (1 << 127) - 1), big.pow(65537 + (1 << 70), (1 << 127) - 1))
failures = failures + check("powm.reopen_wins", powm(big, 0 - 0, 1), -7)
failures = failures + check("isqrt", root(big) * root(big) <= big, true)
failures = failures + check("isqrt.exact", root((1 << 100) * (1 << 100)) == (1 << 100), true)
failures = failures + check("reopen.direct", probe(big), "reopened:" + big.to_s())
demoted_results = demoted(big)
failures = failures + check("demoted.cmp", demoted_results[0], 0)
failures = failures + check("demoted.abs", demoted_results[1], 5)
failures = failures + check("demoted.tos", demoted_results[2], "5")
failures = failures + check("demoted.neg_abs", demoted_results[3], 5)

if failures == 0
  << "bigint_core_receiver_locked_direct_spec: all checks passed"
else
  << "bigint_core_receiver_locked_direct_spec: " + failures.to_s() + " failures"
  exit(1)
