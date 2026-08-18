# Distinct positive five-limb BigInt multiplication. This preserves C's
# exact generic schoolbook row decomposition from native Tungsten.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul5(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 256

# Minimum normalized five-limb magnitudes produce exactly nine limbs.
check_mul5("minimum", base, base + 1, 9)
check_mul5("ordinary_nine", base + 37, base * 17 + 91, 9)

# High-bit inputs force a ten-limb product.
check_mul5("high_bit", (1 << 319) + 29, (1 << 319) + 43, 10)
check_mul5("maximum", (1 << 320) - 1, (1 << 320) - 3, 10)

# Equal numeric values in distinct boxes are multiplication, not squaring.
equal_left = base + 37
equal_right = (base + 38) - 1
check_mul5("distinct_equal", equal_left, equal_right, 9)

# Pointer identity remains the already-retained sqr@5 route.
square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

# Sign overlays and negative headers remain on the existing signed C route.
positive = (1 << 319) + 71
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
four_a = (1 << 192) + 29
four_b = (1 << 193) + 31
six_a = (1 << 320) + 37
six_b = (1 << 321) + 41
check("control.four", four_a * four_b,
      ccall("w_bigint_mul_builtin_exact", four_a, four_b))
check("control.six", six_a * six_b,
      ccall("w_bigint_mul_builtin_exact", six_a, six_b))

# Deterministic public-operator differential across both result widths.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  alow = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  amid0 = state
  state = (state * 3202034522624059733 + 1) & mask64
  amid1 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  amid2 = state
  atop = ((state ^ (state >> 23)) + i + 1) & mask64
  if atop == 0
    atop = 1
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  blow = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  bmid0 = state
  state = (state * 3202034522624059733 + 1) & mask64
  bmid1 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  bmid2 = state
  btop = ((state ^ (state >> 29)) + i + 3) & mask64
  if btop == 0
    btop = 1
  left = (atop << 256) + (amid2 << 192) + (amid1 << 128) + (amid0 << 64) + alow
  right = (btop << 256) + (bmid2 << 192) + (bmid1 << 128) + (bmid0 << 64) + blow
  got = left * right
  want = ccall("w_bigint_mul_builtin_exact", left, right)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)
<< "bigint_mul5_source_spec: all checks passed"
