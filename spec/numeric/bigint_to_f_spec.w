# BigInt#to_f — pins the native Tungsten unsigned-limb magnitude walk.
# These rows cover exact rounding at and beyond the 53-bit mantissa boundary,
# an unsigned limb whose high bit is set, sign-overlay composition, and the
# finite/infinity seam on both engines.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

one = (1 << 60) + 12345
check("one_limb_type", type(one.to_f), "Float")
check("one_limb_div", one.to_f / (1 << 60).to_f > 1.0, true)

# Exactly representable: 2^100
p100 = 1 << 100
check("pow2_exact", p100.to_f / (1 << 50).to_f, (1 << 50).to_f)

# Rounding at the mantissa boundary: 2^53 + 1 rounds to 2^53
m = (1 << 53) + 1
check("mantissa_round", m.to_f, (1 << 53).to_f)

# The limb conversion must be unsigned: 2^64 - 1 rounds to 2^64, not -1.
u64_max = (1 << 64) - 1
check("unsigned_limb", u64_max.to_f, (1 << 64).to_f)

# Negative receivers carry sign through the overlay composition
check("negative", (0 - p100).to_f, 0.0 - p100.to_f)

# Multi-limb magnitude
big = (1 << 200) + (1 << 130) + 7
check("multi_type", type(big.to_f), "Float")
check("multi_ratio", big.to_f / (1 << 100).to_f > (1 << 99).to_f, true)

# A normalized 17-limb magnitude starts at 2^1024 and converts to infinity.
overflow = (1 << 1024).to_f
check("overflow_type", type(overflow), "Float")
check("overflow_infinite", overflow.infinite?, true)
check("negative_overflow", (0 - (1 << 1024)).to_f < ~0.0, true)

# Conversion feeds float division exactly
check("arith", p100.to_f / p100.to_f, ~1.0)

<< "bigint_to_f_spec: all checks passed"
