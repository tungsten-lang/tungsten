# Distinct positive seven-limb BigInt multiplication. This preserves C's
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

-> check_mul7(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 384

check_mul7("minimum", base, base + 1, 13)
check_mul7("ordinary_thirteen", base + 37, base * 17 + 91, 13)
check_mul7("high_bit", (1 << 447) + 29, (1 << 447) + 43, 14)
check_mul7("maximum", (1 << 448) - 1, (1 << 448) - 3, 14)

equal_left = base + 37
equal_right = (base + 38) - 1
check_mul7("distinct_equal", equal_left, equal_right, 13)

square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

positive = (1 << 447) + 71
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

six_a = (1 << 320) + 29
six_b = (1 << 321) + 31
eight_a = (1 << 448) + 37
eight_b = (1 << 449) + 41
check("control.six", six_a * six_b,
      ccall("w_bigint_mul_builtin_exact", six_a, six_b))
check("control.eight", eight_a * eight_b,
      ccall("w_bigint_mul_builtin_exact", eight_a, eight_b))

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  a0 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  a1 = state
  state = (state * 3202034522624059733 + 1) & mask64
  a2 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  a3 = state
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  a4 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  a5 = state
  atop = ((state ^ (state >> 23)) + i + 1) & mask64
  if atop == 0
    atop = 1
  state = (state * 3202034522624059733 + 1) & mask64
  b0 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  b1 = state
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  b2 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  b3 = state
  state = (state * 3202034522624059733 + 1) & mask64
  b4 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  b5 = state
  btop = ((state ^ (state >> 29)) + i + 3) & mask64
  if btop == 0
    btop = 1
  left = (atop << 384) + (a5 << 320) + (a4 << 256) + (a3 << 192) + (a2 << 128) + (a1 << 64) + a0
  right = (btop << 384) + (b5 << 320) + (b4 << 256) + (b3 << 192) + (b2 << 128) + (b1 << 64) + b0
  got = left * right
  want = ccall("w_bigint_mul_builtin_exact", left, right)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)
<< "bigint_mul7_source_spec: all checks passed"
