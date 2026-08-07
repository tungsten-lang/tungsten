# Exact-tower equality (Erik's rule, 2026-08-07): Integer, Rational, and
# Decimal are all EXACT representations, so `==` compares them by
# mathematical value — 2.0 == 2, 1/2 == 0.5, 4/2 == 2. Binary Floats are
# approximations by construction and equal only other Floats: ordering
# still crosses the boundary (~2.0 < 3 works), equality deliberately does
# not (~2.0 == 2.0 is false). Comparison is exact — mixed pairs become
# integer (n, d) pairs and cross-multiply in the bigint domain, never
# rounding through a double.
#
# Hash keys follow: equal values hash equal, so a Decimal 2.0 key hits an
# Integer 2 entry and 1/2 hits 0.5.
#
# Run both engines: `bin/tungsten spec/numeric/exact_equality_spec.w`
#            and: `bin/tungsten -o /tmp/eeq spec/numeric/exact_equality_spec.w && /tmp/eeq`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- Integer ↔ Decimal --
check("int_dec", 2.0 == 2, true)
check("dec_int", 2 == 2.0, true)
check("int_dec_frac", 2.5 == 2, false)
check("int_dec_neq", 2.0 != 2, false)

# -- Rational ↔ Decimal --
check("rat_dec_half", 1/2 == 0.5, true)
check("rat_dec_three_halves", 3/2 == 1.5, true)
check("rat_dec_unequal", 3/2 == 1.6, false)

# -- Rational ↔ Integer --
check("rat_int_reduced", 4/2 == 2, true)
check("rat_int_unequal", 3/2 == 1, false)

# -- BigInt ↔ Decimal (exact at any magnitude: +1 must break equality,
# which a double round-trip would silently absorb) --
check("big_dec", 10 ** 20 == 1.0e20, true)
check("big_dec_off", 10 ** 20 + 1 == 1.0e20, false)

# -- Floats equal only Floats --
check("float_float", ~2.0 == ~2.0, true)
check("float_dec", ~2.0 == 2.0, false)
check("float_int", ~2.0 == 2, false)
check("int_float", 2 == ~2.0, false)
check("float_dec_neq", ~2.0 != 2.0, true)

# -- ordering still crosses the float boundary --
check("float_orders", ~2.0 < 3 && ~2.0 > 1.5, true)

# -- exactness survives arithmetic --
check("decimal_sum", 0.1 + 0.2 == 0.3, true)
check("decimal_sum_int", 0.5 + 0.5 == 1, true)
check("rational_sum", 1/4 + 1/4 == 0.5, true)

# -- hash keys unify across the exact tower --
h = {2 => "int"}
check("hash_dec_hits_int", h[2.0], "int")
h2 = {0.5 => "half"}
check("hash_rat_hits_dec", h2[1/2], "half")
h3 = {~2.0 => "float"}
check("hash_int_misses_float", h3[2], nil)
