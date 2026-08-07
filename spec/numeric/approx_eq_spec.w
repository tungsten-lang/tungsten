# `a ≈ b` — approximate equality at == precedence.
# |a-b| <= 1e-12 · max(1, |a|, |b|): relative above magnitude 1, absolute
# below it. Every numeric coerces through the same double path, so
# ~2.0 ≈ 2 is true where ~2.0 == 2 (exact-tower rule) is not. Quantities
# compare after unit conversion; dimension mismatch is false, not an
# error. Non-numeric pairs fall back to exact ==.
#
# Run: bin/tungsten spec/numeric/approx_eq_spec.w   (and -o / --ruby)

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()

# -- the classic float-noise case --
check("float_noise", ~0.1 + ~0.2 ≈ ~0.3, true)
check("float_noise_ne", ~0.1 + ~0.2 == ~0.3, false)

# -- crosses the float/exact boundary (== deliberately does not) --
check("float_int", ~2.0 ≈ 2, true)
check("float_dec", ~2.0 ≈ 2.0, true)
check("dec_int", 2.0 ≈ 2, true)
check("rat_dec", 1/2 ≈ 0.5, true)

# -- tight but not sloppy --
check("close_passes", ~1.0 ≈ ~1.0000000000001, true)
check("meaningful_diff_fails", ~1.0 ≈ ~1.0001, false)
check("spectral_leak_fails", ~0.99971 ≈ 1, false)

# -- near zero: absolute term --
check("tiny_vs_zero", ~1.0e-15 ≈ 0, true)
check("small_vs_zero_fails", ~1.0e-9 ≈ 0, false)

# -- large magnitudes: relative term --
big = ~1.0e100
check("large_relative", big ≈ big * ~1.0000000000001, true)
check("large_relative_fails", big ≈ big * ~1.001, false)

# -- exact pairs still work through it --
check("int_int", 2 ≈ 2, true)
check("int_int_ne", 2 ≈ 3, false)

# -- quantities: converts, then compares --
check("quantity_same", 1 km ≈ 1000 m, true)
check("quantity_close", 1 km ≈ 1000.0000000001 m, true)
check("quantity_off", 1 km ≈ 999 m, false)
check("quantity_dim_mismatch", 1 km ≈ 1 kg, false)

# -- non-numerics fall back to exact equality --
check("string_eq", "abc" ≈ "abc", true)
check("string_ne", "abc" ≈ "abd", false)

# -- trig results: exact π-quantity path vs approximate check --
check("sin_approx_zero", Math.sin(~3.14159265358979) ≈ 0, true)
