# Algebraic BigInt identities should preserve immutable value semantics while
# returning the existing heap value whenever the result is literally an input.
# BigInt#neg! is used only as an identity probe: if result aliases original,
# mutating result is visible through original.  The second neg! restores it.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_alias(name, original, result)
  result.neg!
  check(name, original < 0, true)
  result.neg!

x = (10 ** 80) + 123456789
m = (10 ** 90) + 987654321

check_alias("identity.add_zero", x, x + 0)
check_alias("identity.sub_zero", x, x - 0)
check_alias("identity.mul_one", x, x * 1)
check_alias("identity.div_one", x, x / 1)
check_alias("identity.shl_zero", x, x << 0)
check_alias("identity.shr_zero", x, x >> 0)
check_alias("identity.and_self", x, x & x)
check_alias("identity.and_neg_one", x, x & -1)
check_alias("identity.or_self", x, x | x)
check_alias("identity.or_zero", x, x | 0)
check_alias("identity.xor_zero", x, x ^ 0)
check_alias("identity.gcd_zero", x, x.gcd(0))
check_alias("identity.gcd_self", x, x.gcd(x))
check_alias("identity.lcm_one", x, x.lcm(1))
check_alias("identity.lcm_self", x, x.lcm(x))
check_alias("identity.pow_one", x, x ** 1)
check_alias("identity.powmod_one", x, x.modpow(1, m))

check("identity.sub_self", x - x, 0)
check("identity.div_self", x / x, 1)
check("identity.mod_one", x % 1, 0)
check("identity.mod_self", x % x, 0)
check("identity.xor_self", x ^ x, 0)
check("identity.lcm_zero", x.lcm(0), 0)
check("identity.pow_zero", x ** 0, 1)
check("identity.powmod_mod_one", x.modpow(17, 1), 0)
check("identity.powmod_base_one", 1.modpow(17, m), 1)
check("identity.powmod_base_neg_one_even", (-1).modpow(16, m), 1)
check("identity.powmod_base_neg_one_odd", (-1).modpow(17, m), m - 1)
check("identity.xor_neg_one", x ^ -1, 0 - x - 1)
check("identity.mul_neg_one", x * -1, 0 - x)
check("identity.div_neg_one", x / -1, 0 - x)
check("identity.gcd_negative_self", (0 - x).gcd(0 - x), x)
check("identity.lcm_negative_self", (0 - x).lcm(0 - x), x)

# Compound assignment consumes/rebinds the LHS binding, never a shared value.
compound_old = (10 ** 80) + 77
compound_alias = compound_old
compound_old += 1
check("compound.alias_preserves_old_value", compound_alias, (10 ** 80) + 77)
check("compound.rebinds_lhs", compound_old, (10 ** 80) + 78)

<< "bigint_identity_spec: all checks passed"
