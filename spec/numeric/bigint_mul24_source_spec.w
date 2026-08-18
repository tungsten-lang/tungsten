# Distinct positive twenty-four-limb BigInt multiplication. This preserves C's
# exact selected top-level difference-form leaf from native Tungsten.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul24(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 1472

check_mul24("minimum", base, base + 1, 47)
check_mul24("ordinary_forty_seven", base + 37, base * 17 + 91, 47)
check_mul24("high_bit", (1 << 1535) + 29, (1 << 1535) + 43, 48)
check_mul24("maximum", (1 << 1536) - 1, (1 << 1536) - 3, 48)

equal_left = base + 37
equal_right = (base + 38) - 1
check_mul24("distinct_equal", equal_left, equal_right, 47)

square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

positive = (1 << 1535) + 71
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

twenty_three_a = (1 << 1408) + 29
twenty_three_b = (1 << 1409) + 31
twenty_five_a = (1 << 1536) + 37
twenty_five_b = (1 << 1537) + 41
check("control.twenty_three", twenty_three_a * twenty_three_b,
      ccall("w_bigint_mul_builtin_exact", twenty_three_a, twenty_three_b))
check("control.twenty_five", twenty_five_a * twenty_five_b,
      ccall("w_bigint_mul_builtin_exact", twenty_five_a, twenty_five_b))

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 1_000
  left = 0
  right = 0
  j = 0
  while j < 24
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    alimb = state
    state = (state * 2862933555777941757 + 3037000493) & mask64
    blimb = state
    if j == 23
      alimb = ((alimb ^ (alimb >> 23)) + i + 1) & mask64
      blimb = ((blimb ^ (blimb >> 29)) + i + 3) & mask64
      if alimb == 0
        alimb = 1
      if blimb == 0
        blimb = 1
    left += alimb << (j * 64)
    right += blimb << (j * 64)
    j += 1
  got = left * right
  want = ccall("w_bigint_mul_builtin_exact", left, right)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 1_000)
<< "bigint_mul24_source_spec: all checks passed"
