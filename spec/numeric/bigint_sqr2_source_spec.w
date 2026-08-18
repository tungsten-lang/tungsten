# Pointer-identical two-limb BigInt squaring. On macOS ARM64 this is the
# exact native Tungsten port of bigint_mul_positive_equal's n==2 square arm.

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
  check(name + ".value", got.to_s(), expected)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".receiver_unchanged", value.to_s(), before)

base = 1 << 64

check_square("minimum", base,
             "340282366920938463463374607431768211456", 3)
check_square("ordinary", base + 37,
             "340282366920938464828433668886275032409", 3)
check_square("high_bit", (1 << 127) + 29,
             "28948022309329048855892746252171976973185684807117356450302259617499560543049", 4)
check_square("maximum", (1 << 128) - 1,
             "115792089237316195423570985008687907852589419931798687112530834793049593217025", 4)

# Negation normally uses the tag-sign overlay while retaining header +2.
# C admits this raw-header identity shape and produces the same positive square.
overlay_negative = 0 - (base + 37)
check_square("overlay_negative", overlay_negative,
             "340282366920938464828433668886275032409", 3)

# A real negative header is rejected by the raw positive identity gate and
# therefore remains on the existing generic signed C route.
header_negative = base + 37
header_negative.neg!
check("header_negative.raw_header", header_negative.__spec_header_size(), -2)
check_square("header_negative", header_negative,
             "340282366920938464828433668886275032409", 3)

# Equal numeric values in distinct boxes must remain ordinary multiplication.
left = base + 17
right = base + 17
check("control.distinct", (left * right).to_s(),
      "340282366920938464090563905937892966689")

# Deterministic public-operator differential across both result widths. The
# C oracle supplies the expected value and exact normalized header; toggling
# the tag sign covers the raw-positive-header overlay shape admitted by C.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  low = state
  high = ((state ^ (state >> 23)) + i + 1) & mask64
  if high == 0
    high = 1
  value = (high << 64) + low
  if (i & 1) == 1
    value = 0 - value
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
    << "FAIL differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)

<< "bigint_sqr2_source_spec: all checks passed"
