# Positive four-limb BigInt times positive one-limb BigInt. On macOS ARM64
# this is the exact native Tungsten port of the boxed C mul1@4 arm.

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

# The final carry word is zero, so the capacity-eight result publishes four
# limbs even though the leaf writes limb four unconditionally.
check_mul1("no_top_carry", base ** 3 + 1, heap + 1,
           "1766847064778390606685032887423682351616907104542035060477332140303843329", 4)

# A larger high limb drives the same serial carry chain into limb five.
check_mul1("ordinary_carry", base ** 3 * 99 + 12345, (1 << 63) + 11,
           "5731708417247151680302527547766146790554038922822356647202478015208005709206131", 5)

# Maximum inputs exercise carry propagation at every join and top publication.
check_mul1("maximum", base ** 4 - 1, base - 1,
           "2135987035920910082279229616932235919179133537347964862093771623156579161741164519270975247745025", 5)

# Neighboring widths, signs, and squaring retain their existing C routes.
one = (1 << 63) + 29
three = base * base + 1
five = (1 << 319) + 37
check("control.three_by_one.roundtrip", (three * one) / one, three)
check("control.five_by_one.roundtrip", (five * one) / one, five)
check("control.negative_wide", ((0 - (base ** 3 + 1)) * one) / one,
      0 - (base ** 3 + 1))
check("control.negative_word", ((base ** 3 + 1) * (0 - one)) / (0 - one),
      base ** 3 + 1)
check("control.square", (base ** 3 + 1) * (base ** 3 + 1),
      (base ** 3 + 1) ** 2)

# Deterministic carry/no-carry sweep. Division and remainder remain independent
# C kernels, so they validate the complete product without cloning this leaf.
i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 192) + ((i + 17) << 128) + ((i + 9) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 4 : 5
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_4_source_spec: all checks passed"
