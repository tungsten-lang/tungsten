# Distinct positive three-limb BigInt addition. On macOS ARM64 this is the
# exact native Tungsten port of bigint_add_equal_fast's n==3 arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_add3(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left + right
  oracle = ccall("w_bigint_add", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right + left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

base = 1 << 128

# No carry from the top limb: the result remains normalized at three limbs.
check_add3("minimum", base, base + 1, 3)
check_add3("ordinary", base * 17 + 37, base * 19 + 91, 3)

# Carry from the top limb publishes the fourth limb and grows the header.
check_add3("high_bit", (1 << 191) + 29, (1 << 191) + 43, 4)
check_add3("maximum", (1 << 192) - 1, (1 << 192) - 3, 4)

# Equal numeric values in distinct boxes still take the binary-add leaf.
equal_left = base + 37
equal_right = (base + 38) - 1
check_add3("distinct_equal", equal_left, equal_right, 3)

# Signed shapes and neighboring equal widths retain the existing C routes.
positive = (1 << 191) + 71
other = base * 31 + 17
negative = 0 - positive
check("control.mixed_sign", negative + other,
      ccall("w_bigint_add", negative, other))
check("control.both_negative", negative + (0 - other),
      ccall("w_bigint_add", negative, 0 - other))
two_a = (1 << 64) + 29
two_b = (1 << 65) + 31
four_a = (1 << 192) + 37
four_b = (1 << 193) + 41
check("control.two", two_a + two_b, ccall("w_bigint_add", two_a, two_b))
check("control.four", four_a + four_b, ccall("w_bigint_add", four_a, four_b))

# Deterministic public-operator differential across both result widths.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 10_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  alow = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  amid = state
  atop = ((state ^ (state >> 23)) + i + 1) & mask64
  if atop == 0
    atop = 1
  state = (state * 3202034522624059733 + 1) & mask64
  blow = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  bmid = state
  btop = ((state ^ (state >> 29)) + i + 3) & mask64
  if btop == 0
    btop = 1
  left = (atop << 128) + (amid << 64) + alow
  right = (btop << 128) + (bmid << 64) + blow
  got = left + right
  oracle = ccall("w_bigint_add", left, right)
  if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
    << "FAIL differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 10_000)

<< "bigint_add3_equal_source_spec: all checks passed"
