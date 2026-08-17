# Positive two-limb BigInt times positive one-limb BigInt. On macOS ARM64
# this is the exact native Tungsten port of bigint_mul_ui_any's n==2 arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul1(name, wide, word, expected, expected_size)
  got = wide * word
  check(name + ".value", got.to_s(), expected)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", word * wide, got)
  check(name + ".roundtrip", got / word, wide)

base = 1 << 64
heap = 1 << 48

# The final carry word is zero, so the cap-four result publishes two limbs.
check_mul1("no_top_carry", base + 1, heap + 1,
           "5192296858534846075556045015482369", 2)

# An ordinary high-word multiplier publishes the third carry limb.
check_mul1("ordinary_carry", base * 99 + 12345, (1 << 63) + 11,
           "16843977162586454075388075159114435662451", 3)

# Maximum inputs exercise carry from the joined middle word into limb two.
check_mul1("maximum", base * base - 1, base - 1,
           "6277101735386680763495507056286727952620534092958556749825", 3)

# Neighboring widths and sign shapes remain on their retained C routes.
one = (1 << 63) + 29
three = (1 << 191) + 37
check("control.one_by_one", (heap + 17) * one,
      2596148429267570619752649020408301)
check("control.three_by_one.roundtrip", (three * one) / one, three)
check("control.negative_wide", ((0 - (base + 1)) * one) / one,
      0 - (base + 1))
check("control.negative_word", ((base + 1) * (0 - one)) / (0 - one),
      base + 1)

<< "bigint_mul1_2_source_spec: all checks passed"
