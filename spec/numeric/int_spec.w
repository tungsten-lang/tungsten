# spec: compiled
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

# Int#prime?, prime_12k?, prime_30k? across all runtime tiers.
check("prime.negative", (-7).prime?, false)
check("prime.zero", 0.prime?, false)
check("prime.one", 1.prime?, false)
check("prime.two", 2.prime?, true)
check("prime.three", 3.prime?, true)
check("prime.four", 4.prime?, false)
check("prime.sixty_one", 61.prime?, true)
check("prime.sixty_three", 63.prime?, false)
check("prime.sixty_seven", 67.prime?, true)
check("prime.sq_37", 1369.prime?, false)
check("prime.below_41sq", 1669.prime?, true)
check("prime.at_41sq", 1681.prime?, false)
check("prime.below_cutoff", 999983.prime?, true)
check("prime.below_cutoff_comp", 999997.prime?, false)
check("prime.above_cutoff_comp", 1000001.prime?, false)
check("prime.above_cutoff", 1000003.prime?, true)
check("prime.spsp_2047", 2047.prime?, false)
check("prime.spsp_3215031751", 3215031751.prime?, false)
check("prime.max_u32_prime", 4294967291.prime?, true)
check("prime.above_u32_prime", 4294967311.prime?, true)
check("prime.jaeschke_4759123141", 4759123141.prime?, false)
check("prime.b4_1122004669633", 1122004669633.prime?, false)
check("prime.b5_2152302898747", 2152302898747.prime?, false)
check("prime.b6_3474749660383", 3474749660383.prime?, false)
check("prime.max_int48_prime", 140737488355213.prime?, true)
check("prime.max_int48_comp", 140737488355327.prime?, false)
check("prime_12k.small", 5.prime_12k?, true)
check("prime_12k.large", 140737488355213.prime_12k?, true)
check("prime_12k.comp", 4759123141.prime_12k?, false)
check("prime_30k.small", 7.prime_30k?, true)
check("prime_30k.large", 140737488355213.prime_30k?, true)
check("prime_30k.comp", 4759123141.prime_30k?, false)

# isqrt and isqrt_rem across Int, 1-limb BigInt, and 2-limb BigInt.
check("isqrt.zero", 0.isqrt, 0)
check("isqrt.one", 1.isqrt, 1)
check("isqrt.max_int48", 140737488355327.isqrt, 11863283)
check("isqrt.exact_sq", (11863283 * 11863283).isqrt, 11863283)
check("isqrt.just_below_sq", (11863283 * 11863283 - 1).isqrt, 11863282)
check("isqrt_rem.int", 105.isqrt_rem, [10, 5])
check("isqrt_rem.bigint_2limb", ((1 << 90) + 77).isqrt_rem, [1 << 45, 77])

# bit_length, popcount, scan1, scan0.
check("bit_length.zero", 0.bit_length, 0)
check("bit_length.minus_one", (-1).bit_length, 0)
check("bit_length.255", 255.bit_length, 8)
check("bit_length.256", 256.bit_length, 9)
check("bit_length.neg_256", (-256).bit_length, 8)
check("bit_length.neg_257", (-257).bit_length, 9)
check("bit_length.min_int48", (-140737488355328).bit_length, 47)
check("bit_length.bigint_pos", (1 << 100).bit_length, 101)
check("bit_length.bigint_neg_pow2", (0 - (1 << 100)).bit_length, 100)
check("bit_length.bigint_neg_nonpow2", (0 - ((1 << 100) + 1)).bit_length, 101)
check("popcount.zero", 0.popcount, 0)
check("popcount.255", 255.popcount, 8)
check("popcount.neg_255", (-255).popcount, 8)
check("popcount.min_int48", (-140737488355328).popcount, 1)
check("scan0.neg_bigint_pow2", (0 - (1 << 100)).scan0(0), 0)
check("scan0.neg_bigint_At99", (0 - (1 << 100)).scan0(99), 99)
check("scan0.neg_bigint_At100", (0 - (1 << 100)).scan0(100), -1)
check("scan1.neg_bigint_pow2", (0 - (1 << 100)).scan1(0), 100)
check("scan1.int_neg", (-12).scan1(0), 2)
check("scan1.int_neg_hi", (-12).scan1(3), 4)
check("scan0.int_neg", (-12).scan0(2), 3)
check("scan0.int_minus_one", (-1).scan0(0), -1)
check("trailing_zeros.int", (-140737488355328).trailing_zeros, 47)
check("hamdist.same_neg", (-5).hamdist(-3), 2)
check("hamdist.diff_sign", (-5).hamdist(3), -1)
check("tstbit.int_neg", (-12).tstbit(2), 1)
check("tstbit.int_sign", (-12).tstbit(100), 1)
check("setbit.int_neg", (-140737488355328).setbit(0), -140737488355327)
check("clrbit.int_neg", (-1).clrbit(46), -70368744177665)
check("combit.int_neg", (-1).combit(46), -70368744177665)
check("cmpabs.int_min", (-140737488355328).cmpabs(140737488355327), 1)
check("fdiv.int", (-7).fdiv(3), -3)
check("fmod.int", (-7).fmod(3), 2)
check("cdiv.int", 7.cdiv(3), 3)
check("cmod.int", 7.cmod(3), -2)
check("congruent.int_large", 140737488355300.congruent?(-140737488355300, 100), true)

# perfect_square? and perfect_power?.
check("perfect_square.int_true", (11863283 * 11863283).perfect_square?, true)
check("perfect_square.int_false", (11863283 * 11863283 - 1).perfect_square?, false)
check("perfect_square.2limb_true", (((1 << 50) + 3) ** 2).perfect_square?, true)
check("perfect_square.2limb_false", (((1 << 50) + 3) ** 2 + 1).perfect_square?, false)
check("perfect_square.4limb_true", (((1 << 110) + 7) ** 2).perfect_square?, true)
check("perfect_square.4limb_false", (((1 << 110) + 7) ** 2 + 1).perfect_square?, false)
check("perfect_power.1limb_cube", (123456 ** 3).perfect_power?, true)
check("perfect_power.1limb_nonpower", (123456 ** 3 + 1).perfect_power?, false)

# Fibonacci and Lucas table boundary.
check("fib.0", 0.fib, 0)
check("fib.1", 1.fib, 1)
check("fib.70", 70.fib, 190392490709135)
check("fib.93", 93.fib, 12200160415121876738)
check("fib.94", 94.fib, 19740274219868223167)
check("fib2.93", 93.fib2, [12200160415121876738, 7540113804746346429])
check("lucas.0", 0.lucas, 2)
check("lucas.1", 1.lucas, 1)
check("lucas.92", 92.lucas, 16860207025497407047)
check("lucas.93", 93.lucas, 27280388024614569596)
check("lucas2.92", 92.lucas2, [16860207025497407047, 10420180999117162549])

# digits and factor.
check("digits.base10", 9081726354.digits, [4, 5, 3, 6, 2, 7, 1, 8, 0, 9])
check("digits.base16", 255.digits(16), [15, 15])
check("factor.large_prime", 1000000007.factor.primes, [1000000007])
check("factor.semiprime", (97 * 1000000007).factor.primes, [97, 1000000007])
check("modpow.32bit", 3.modpow(1000000, 1000000007), 64935414)
check("modpow.48bit", 5.modpow(123456789, 140737488355213), 4502006178222)
