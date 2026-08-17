# Positive eight-limb BigInt times positive one-limb BigInt: exact C port.

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
check_mul1("no_top_carry", base ** 7 + 1, heap + 1,
           "204586912993509593714548651658615496337348015882225902984066397824068643765491340319492494168292336012981131521538065200597684800295770881909638299649", 8)
check_mul1("ordinary_carry", base ** 7 * 99 + 12345, (1 << 63) + 11,
           "663686492532158557220441608169105287118442234909360410108431733252716687135183402259408962514752058172878631207519582412931203228415336844495441771570008691", 9)
check_mul1("maximum", base ** 8 - 1, base - 1,
           "247330401473104534047094713089704592935557324103005993786583690272304831728808305726594637031169498012795797127849235911661333176120265159113792272289946579523429049433063425", 9)

one = (1 << 63) + 29
seven = base ** 6 + 1
nine = (1 << 575) + 37
check("control.seven_by_one.roundtrip", (seven * one) / one, seven)
check("control.nine_by_one.roundtrip", (nine * one) / one, nine)
check("control.negative_wide", ((0 - (base ** 7 + 1)) * one) / one,
      0 - (base ** 7 + 1))
check("control.negative_word", ((base ** 7 + 1) * (0 - one)) / (0 - one),
      base ** 7 + 1)
check("control.square", (base ** 7 + 1) * (base ** 7 + 1),
      (base ** 7 + 1) ** 2)

i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 448) + ((i + 21) << 384) + ((i + 19) << 320) + ((i + 17) << 256) + ((i + 15) << 192) + ((i + 13) << 128) + ((i + 9) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 8 : 9
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_8_source_spec: all checks passed"
