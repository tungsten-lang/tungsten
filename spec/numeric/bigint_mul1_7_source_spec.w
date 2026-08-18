# Positive seven-limb BigInt times positive one-limb BigInt: exact C port.

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
check_mul1("no_top_carry", base ** 6 + 1, heap + 1,
           "11090678776483298840319853131051547092785848445117071380421188787905153179515906737881669121627169726655819728761255375418863648769", 7)
check_mul1("ordinary_carry", base ** 6 * 99 + 12345, (1 << 63) + 11,
           "35978516852632541125100313238329812312677122023078639417665600924978516183008888721870048019491758851087880771079962803076175634268033651", 8)
check_mul1("maximum", base ** 7 - 1, base - 1,
           "13407807929942597098847186273910239236930042012704388843369920083034445969792056777621235010053505504363840807472722485292991361205680373566154973667917825", 8)

one = (1 << 63) + 29
six = base ** 5 + 1
eight = (1 << 511) + 37
check("control.six_by_one.roundtrip", (six * one) / one, six)
check("control.eight_by_one.roundtrip", (eight * one) / one, eight)
check("control.negative_wide", ((0 - (base ** 6 + 1)) * one) / one,
      0 - (base ** 6 + 1))
check("control.negative_word", ((base ** 6 + 1) * (0 - one)) / (0 - one),
      base ** 6 + 1)
check("control.square", (base ** 6 + 1) * (base ** 6 + 1),
      (base ** 6 + 1) ** 2)

i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 384) + ((i + 19) << 320) + ((i + 17) << 256) + ((i + 15) << 192) + ((i + 13) << 128) + ((i + 9) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 7 : 8
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_7_source_spec: all checks passed"
