# Distinct positive seventeen-limb BigInt multiplication. This preserves C's
# exact fixed bn_mul_eq17 leaf from native Tungsten.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul17(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left * right
  oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right * left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 1024

check_mul17("minimum", base, base + 1, 33)
check_mul17("ordinary_thirty_three", base + 37, base * 17 + 91, 33)
check_mul17("high_bit", (1 << 1087) + 29, (1 << 1087) + 43, 34)
check_mul17("maximum", (1 << 1088) - 1, (1 << 1088) - 3, 34)

equal_left = base + 37
equal_right = (base + 38) - 1
check_mul17("distinct_equal", equal_left, equal_right, 33)

square_value = base + 123
check("control.identity_square", square_value * square_value,
      ccall("w_bigint_mul_builtin_exact", square_value, square_value))

positive = (1 << 1087) + 71
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

sixteen_a = (1 << 960) + 29
sixteen_b = (1 << 961) + 31
eighteen_a = (1 << 1088) + 37
eighteen_b = (1 << 1089) + 41
check("control.sixteen", sixteen_a * sixteen_b,
      ccall("w_bigint_mul_builtin_exact", sixteen_a, sixteen_b))
check("control.eighteen", eighteen_a * eighteen_b,
      ccall("w_bigint_mul_builtin_exact", eighteen_a, eighteen_b))

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 1_000
  left = 0
  right = 0
  j = 0
  while j < 17
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    alimb = state
    state = (state * 2862933555777941757 + 3037000493) & mask64
    blimb = state
    if j == 16
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
<< "bigint_mul17_source_spec: all checks passed"
