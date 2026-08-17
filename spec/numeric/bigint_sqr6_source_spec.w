# Pointer-identical six-limb BigInt squaring. On macOS ARM64 this is the
# exact native Tungsten port of bigint_mul_positive_equal's n==6 square arm.

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

base = 1 << 320

check_square("minimum", base, 11)
check_square("ordinary", base + 37, 11)
check_square("high_bit", (1 << 383) + 29, 12)
check_square("maximum", (1 << 384) - 1, 12)

# Negation normally uses the tag-sign overlay while retaining header +6.
# C admits this raw-header identity shape and produces the positive square.
overlay_negative = 0 - (base + 37)
check_square("overlay_negative", overlay_negative, 11)

# A real negative header is rejected by the raw positive identity gate and
# therefore remains on the existing generic signed C route.
header_negative = base + 37
header_negative.neg!
check("header_negative.raw_header", header_negative.__spec_header_size(), -6)
check_square("header_negative", header_negative, 11)

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
  limb1 = ((state ^ (state >> 23)) + i + 1) & mask64
  limb2 = ((limb1 ^ (limb1 >> 29)) + i + 3) & mask64
  limb3 = ((limb2 ^ (limb2 >> 31)) + i + 5) & mask64
  limb4 = ((limb3 ^ (limb3 >> 27)) + i + 7) & mask64
  high = ((limb4 ^ (limb4 >> 25)) + i + 9) & mask64
  if high == 0
    high = 1
  value = (high << 320) + (limb4 << 256) + (limb3 << 192) + (limb2 << 128) + (limb1 << 64) + low
  if (i & 1) == 1
    value = 0 - value
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
    << "FAIL differential at " + i.to_s()
    exit 1
  i += 1

check("differential.count", i, 100_000)

<< "bigint_sqr6_source_spec: all checks passed"
