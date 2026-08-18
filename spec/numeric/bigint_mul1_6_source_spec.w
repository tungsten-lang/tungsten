# Positive six-limb BigInt times positive one-limb BigInt: exact C port.

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
check_mul1("no_top_carry", base ** 5 + 1, heap + 1,
           "601226901190103442326742953688152674029880902072644489605588845365015457470947583746432724227051092413239001089", 6)
check_mul1("ordinary_carry", base ** 5 * 99 + 12345, (1 << 63) + 11,
           "1950399306721526723333902367074979963079625731906681862865785748356558094161440236183403460992034745722728770401604211", 7)
check_mul1("maximum", base ** 6 - 1, base - 1,
           "726838724295606890509921801691610055141362320587174446476410459910173841445449629921945328942266354949348255351381243845983899928756225", 7)

one = (1 << 63) + 29
five = base ** 4 + 1
seven = (1 << 447) + 37
check("control.five_by_one.roundtrip", (five * one) / one, five)
check("control.seven_by_one.roundtrip", (seven * one) / one, seven)
check("control.negative_wide", ((0 - (base ** 5 + 1)) * one) / one,
      0 - (base ** 5 + 1))
check("control.negative_word", ((base ** 5 + 1) * (0 - one)) / (0 - one),
      base ** 5 + 1)
check("control.square", (base ** 5 + 1) * (base ** 5 + 1),
      (base ** 5 + 1) ** 2)

i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 320) + ((i + 17) << 256) + ((i + 15) << 192) + ((i + 13) << 128) + ((i + 9) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 6 : 7
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_6_source_spec: all checks passed"
