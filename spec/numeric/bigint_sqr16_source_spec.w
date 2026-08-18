# Pointer-identical sixteen-limb BigInt squaring. This preserves C's exact
# capacity-32 allocation, split square kernel, and +31/+32 publication.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_square(name, value, expected, expected_size)
  before = value.to_s()
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  check(name + ".closed_form", got, expected)
  check(name + ".value", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".oracle_header", got.__spec_header_size(),
        oracle.__spec_header_size())
  check(name + ".receiver_unchanged", value.to_s(), before)

base = 1 << 960
ordinary_square = (1 << 1920) + (74 << 960) + 1369
high_square = (1 << 2046) + (58 << 1023) + 841
maximum_square = (1 << 2048) - (1 << 1025) + 1

check_square("minimum", base, 1 << 1920, 31)
check_square("ordinary", base + 37, ordinary_square, 31)
check_square("high_bit", (1 << 1023) + 29, high_square, 32)
check_square("maximum", (1 << 1024) - 1, maximum_square, 32)

# Tag-overlay negatives retain a raw positive header and enter the same C arm.
overlay_negative = 0 - (base + 37)
check_square("overlay_negative", overlay_negative, ordinary_square, 31)

# A true negative header remains on the generic signed C route.
header_negative = base + 37
header_negative.neg!
check("header_negative.raw_header", header_negative.__spec_header_size(), -16)
check_square("header_negative", header_negative, ordinary_square, 31)

# Equal numeric values in distinct boxes remain ordinary multiplication.
left = base + 17
right = (base + 18) - 1
check("control.distinct", left * right,
      ccall("w_bigint_mul_builtin_exact", left, right))

fifteen = (1 << 896) + 31
seventeen = (1 << 1024) + 43
check("control.fifteen", fifteen * fifteen,
      ccall("w_bigint_mul_builtin_exact", fifteen, fifteen))
check("control.seventeen", seventeen * seventeen,
      ccall("w_bigint_mul_builtin_exact", seventeen, seventeen))

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 1_000
  value = 0
  j = 0
  while j < 16
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    limb = state
    if j == 15
      limb = ((limb ^ (limb >> 23)) + i + 1) & mask64
      if limb == 0
        limb = 1
    value += limb << (j * 64)
    j += 1
  if (i & 1) == 1
    value = 0 - value
  got = value * value
  want = ccall("w_bigint_mul_builtin_exact", value, value)
  if got != want || got.__spec_header_size() != want.__spec_header_size()
    << "FAIL public differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 1_000)
<< "bigint_sqr16_source_spec: all checks passed"
