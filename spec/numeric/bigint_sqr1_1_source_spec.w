# Pointer-identical one-limb BigInt squaring. On macOS ARM64 this is the
# exact native Tungsten port of bigint_mul_positive_11's square arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_square(name, value, expected)
  before = value.to_s()
  got = value * value
  oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  check(name + ".value", got.to_s(), expected)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), 2)
  check(name + ".receiver_unchanged", value.to_s(), before)

base = 1 << 64
heap = 1 << 48

check_square("minimum_heap", heap,
             "79228162514264337593543950336")
check_square("ordinary", (1 << 63) + 29,
             "85070591730234616400799229995519050569")
check_square("maximum", base - 1,
             "340282366920938463426481119284349108225")

# Negation normally uses the tag-sign overlay while retaining the positive
# header. C squares this shape through the same raw one-limb identity arm.
overlay_negative = 0 - (heap + 37)
check_square("overlay_negative", overlay_negative,
             "79228162514285166741820540249")

# C's identity fast arm tests the raw header, not only effective sign. A
# canonical negative-header value therefore stays on the generic C path.
header_negative = heap + 41
header_negative.neg!
check("header_negative.raw_header", header_negative.__spec_header_size(), -1)
check_square("header_negative", header_negative,
             "79228162514287418541634225809")

# A non-identical neighbor must remain ordinary multiplication.
left = heap + 17
right = heap + 29
check("control.distinct", (left * right).to_s(),
      "79228162514277285442472641005")

<< "bigint_sqr1_1_source_spec: all checks passed"
