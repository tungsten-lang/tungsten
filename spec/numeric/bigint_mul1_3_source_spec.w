# Positive three-limb BigInt times positive one-limb BigInt. On macOS ARM64
# this is the exact native Tungsten port of the boxed C mul1@3 arm.

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

# The final carry word is zero, so the cap-four result publishes three limbs.
check_mul1("no_top_carry", base * base + 1, heap + 1,
           "95780971304118393929763610135357787351060101881397249", 3)

# A larger high limb drives the identical serial carry chain into limb four.
check_mul1("ordinary_carry", base * base * 99 + 12345, (1 << 63) + 11,
           "310716535901640698180439074025681474422544069789137498149491", 4)

# Maximum inputs exercise carries at both joins and the top publication.
check_mul1("maximum", base * base * base - 1, base - 1,
           "115792089237316195417293883273301227089434195242432897623336781819375385575425", 4)

# Neighboring widths, signs, and squaring retain their existing C routes.
one = (1 << 63) + 29
two = base + 1
four = (1 << 255) + 37
check("control.two_by_one", two * one,
      170141183460469232275866253890315878429)
check("control.four_by_one.roundtrip", (four * one) / one, four)
check("control.negative_wide", ((0 - (base * base + 1)) * one) / one,
      0 - (base * base + 1))
check("control.negative_word", ((base * base + 1) * (0 - one)) / (0 - one),
      base * base + 1)
check("control.square", (base * base + 1) * (base * base + 1),
      (base * base + 1) ** 2)

# Deterministic carry/no-carry sweep. Division and remainder stay on their
# independent C kernels, so this checks the complete product without another
# copy of the multiplication leaf as the oracle.
i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 128) + ((i + 17) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 3 : 4
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_3_source_spec: all checks passed"
