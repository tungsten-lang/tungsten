# Pointer-identical three-limb BigInt squaring. On macOS ARM64 this is the
# exact native Tungsten port of bigint_mul_positive_equal's n==3 square arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_square(name, value, expected_size)
  before = value.to_s()
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  check(name + ".value", got, oracle)
  check(name + ".decimal", got.to_s(), oracle.to_s())
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".oracle_header", got.__spec_header_size(),
        oracle.__spec_header_size())
  check(name + ".receiver_unchanged", value.to_s(), before)

base = 1 << 128

check_square("minimum", base, 5)
check_square("ordinary", base + 37, 5)
check_square("high_bit", (1 << 191) + 29, 6)
check_square("maximum", (1 << 192) - 1, 6)

# Negation normally uses the tag-sign overlay while retaining header +3.
# C admits this raw-header identity shape and produces the positive square.
overlay_negative = 0 - (base + 37)
check_square("overlay_negative", overlay_negative, 5)

# A real negative header is rejected by the raw positive identity gate and
# therefore remains on the existing generic signed C route.
header_negative = base + 37
header_negative.neg!
check("header_negative.raw_header", header_negative.__spec_header_size(), -3)
check_square("header_negative", header_negative, 5)

# Equal numeric values in distinct boxes remain ordinary multiplication.
left = base + 17
right = base + 17
check("control.distinct", left * right,
      ccall("w_bigint_mul_builtin_exact", left, right))

# Deterministic public-operator differential across both result widths. The C
# oracle supplies the exact value and normalized header; alternating signs
# covers the raw-positive-header overlay shape admitted by C.
mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  low = state
  middle = ((state ^ (state >> 23)) + i + 1) & mask64
  high = ((middle ^ (middle >> 29)) + i + 3) & mask64
  if high == 0
    high = 1
  value = (high << 128) + (middle << 64) + low
  if (i & 1) == 1
    value = 0 - value
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
    << "FAIL differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)

<< "bigint_sqr3_source_spec: all checks passed"
