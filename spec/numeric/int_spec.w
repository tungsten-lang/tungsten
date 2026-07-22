# Core Int number-theory regressions.
# Run: `bin/tungsten -o /tmp/int-spec spec/numeric/int_spec.w && /tmp/int-spec`.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

check("lcm.zero_zero", 0.lcm(0), 0)
check("lcm.left_zero", 0.lcm(17), 0)
check("lcm.right_zero", 17.lcm(0), 0)
check("lcm.positive", 21.lcm(6), 42)
check("lcm.negative", (-21).lcm(6), 42)

# The old multiply-first form promoted this intermediate to BigInt even though
# the exact result fits inline. The divide-first implementation does not.
check("lcm.common_large_factor", 1000000000.lcm(1000000000), 1000000000)
check("lcm.bigint_receiver", 1000000000000000.lcm(1000000000000000), 1000000000000000)
check("lcm.bigint_mixed", 6.lcm(1000000000000000), 3000000000000000)

# Modular inverse (extended Euclidean).
check("invmod.small_prime", 3.invmod(7), 5)
check("invmod.product", (4 * 4.invmod(67)) % 67, 1)
# Product may be negative before reduction; force into [0, m).
neg_prod = ((-3).invmod(7) * (-3)) % 7
if neg_prod < 0
  neg_prod = neg_prod + 7
check("invmod.negative_receiver", neg_prod, 1)
check("invmod.four_inv", 4.invmod(67), 17)

# Legendre symbol via Euler criterion.
check("legendre.zero", 0.legendre(7), 0)
check("legendre.residue", 2.legendre(7), 1)
check("legendre.nonresidue", 3.legendre(7), -1)
check("legendre.square", 4.legendre(13), 1)
check("legendre.nonsquare", 2.legendre(13), -1)
check("legendre.mod_p", 10.legendre(67), 10.legendre(67))
