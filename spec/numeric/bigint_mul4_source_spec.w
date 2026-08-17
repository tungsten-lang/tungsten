# Distinct positive four-limb BigInt multiplication. On macOS ARM64 this is
# the exact native Tungsten port of bigint_mul_positive_equal's n==4 arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul4(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 192

# Minimum normalized four-limb magnitudes produce exactly seven limbs.
check_mul4("minimum", base, base + 1, 7)
check_mul4("ordinary_seven", base + 37, base * 17 + 91, 7)

# High-bit inputs force an eight-limb product.
check_mul4("high_bit", (1 << 255) + 29, (1 << 255) + 43, 8)
check_mul4("maximum", (1 << 256) - 1, (1 << 256) - 3, 8)

# Equal numeric values in distinct boxes are multiplication, not squaring.
equal_left = base + 37
equal_right = (base + 38) - 1
check_mul4("distinct_equal", equal_left, equal_right, 7)

# Pointer identity remains the already-retained sqr@4 route.
square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

# Sign overlays and negative headers remain on the existing signed C route.
positive = (1 << 255) + 71
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
three_a = (1 << 128) + 29
three_b = (1 << 129) + 31
five_a = (1 << 256) + 37
five_b = (1 << 257) + 41
check("control.three", three_a * three_b,
      ccall("w_bigint_mul_builtin_exact", three_a, three_b))
check("control.five", five_a * five_b,
      ccall("w_bigint_mul_builtin_exact", five_a, five_b))

# Deterministic public-operator differential across both result widths.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  alow = 0
  amid0 = 0
  amid1 = 0
  atop = 0
  blow = 0
  bmid0 = 0
  bmid1 = 0
  btop = 0
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  alow = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  amid0 = state
  state = (state * 3202034522624059733 + 1) & mask64
  amid1 = state
  atop = ((state ^ (state >> 23)) + i + 1) & mask64
  if atop == 0
    atop = 1
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  blow = state
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  bmid0 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  bmid1 = state
  btop = ((state ^ (state >> 29)) + i + 3) & mask64
  if btop == 0
    btop = 1
  left = (atop << 192) + (amid1 << 128) + (amid0 << 64) + alow
  right = (btop << 192) + (bmid1 << 128) + (bmid0 << 64) + blow
  got = left * right
  want = ccall("w_bigint_mul_builtin_exact", left, right)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)
<< "bigint_mul4_source_spec: all checks passed"
