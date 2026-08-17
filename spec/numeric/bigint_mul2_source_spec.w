# Distinct positive two-limb BigInt multiplication. On macOS ARM64 this is
# the exact native Tungsten port of bigint_mul_positive_equal's n==2 arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul2(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 64

# Minimum normalized two-limb magnitudes produce exactly three limbs.
check_mul2("minimum", base, base + 1, 3)
check_mul2("ordinary_three", base + 37, base * 17 + 91, 3)

# High-bit inputs force a four-limb product.
check_mul2("high_bit", (1 << 127) + 29, (1 << 127) + 43, 4)
check_mul2("maximum", (1 << 128) - 1, (1 << 128) - 3, 4)

# Equal numeric values in distinct boxes are multiplication, not squaring.
equal_left = base + 37
equal_right = (base + 38) - 1
check_mul2("distinct_equal", equal_left, equal_right, 3)

# Pointer identity remains the already-retained sqr@2 route.
square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

# Sign overlays and negative headers remain on the existing signed C route.
positive = (1 << 127) + 71
other = base * 31 + 17
overlay_negative = 0 - positive
check("control.overlay_mixed", overlay_negative * other,
      ccall("w_bigint_mul_builtin_exact", overlay_negative, other))
check("control.overlay_both", overlay_negative * (0 - other),
      ccall("w_bigint_mul_builtin_exact", overlay_negative, 0 - other))
header_negative = positive
header_negative.neg!
check("control.header_negative", header_negative * other,
      ccall("w_bigint_mul_builtin_exact", header_negative, other))

# Neighboring equal widths retain their existing routes.
one = (1 << 63) + 29
three_a = (1 << 128) + 37
three_b = (1 << 129) + 41
check("control.one", one * (one + 2),
      ccall("w_bigint_mul_builtin_exact", one, one + 2))
check("control.three", three_a * three_b,
      ccall("w_bigint_mul_builtin_exact", three_a, three_b))

# Deterministic public-operator differential across both result widths.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  alow = state
  ahigh = ((state ^ (state >> 23)) + i + 1) & mask64
  if ahigh == 0
    ahigh = 1
  state = (state * 2862933555777941757 + 3037000493) & mask64
  blow = state
  bhigh = ((state ^ (state >> 29)) + i + 3) & mask64
  if bhigh == 0
    bhigh = 1
  left = (ahigh << 64) + alow
  right = (bhigh << 64) + blow
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
    << "FAIL differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)

<< "bigint_mul2_source_spec: all checks passed"
