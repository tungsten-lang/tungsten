# Positive five-limb BigInt times positive one-limb BigInt. On macOS ARM64
# this is the exact native Tungsten port of the boxed C mul1@5 arm.

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

check_mul1("no_top_carry", base ** 4 + 1, heap + 1,
           "32592575621351893172384368330745474147808502986562833280162912830234140253797676687040708609", 5)
check_mul1("ordinary_carry", base ** 4 * 99 + 12345, (1 << 63) + 11,
           "105731358278085049204651159634830166489102676531115443764589572888082450665224878738548993688736371", 6)
check_mul1("maximum", base ** 5 - 1, base - 1,
           "39402006196394479210143053064222703722684717564295894553345588881889069001550169003592046529104256644039592193818625", 6)

one = (1 << 63) + 29
four = base ** 3 + 1
six = (1 << 383) + 37
check("control.four_by_one.roundtrip", (four * one) / one, four)
check("control.six_by_one.roundtrip", (six * one) / one, six)
check("control.negative_wide", ((0 - (base ** 4 + 1)) * one) / one,
      0 - (base ** 4 + 1))
check("control.negative_word", ((base ** 4 + 1) * (0 - one)) / (0 - one),
      base ** 4 + 1)
check("control.square", (base ** 4 + 1) * (base ** 4 + 1),
      (base ** 4 + 1) ** 2)

i = 0
while i < 256
  top = i % 2 == 0 ? 1 : base - 1
  wide = (top << 256) + ((i + 17) << 192) + ((i + 13) << 128) + ((i + 9) << 64) + (i * 65537 + 3)
  word = (1 << 63) + i * 2 + 1
  got = wide * word
  label = "sweep-" + i.to_s()
  check(label + ".quotient", got / word, wide)
  check(label + ".remainder", got % word, 0)
  check(label + ".commuted", word * wide, got)
  expected_size = top == 1 ? 5 : 6
  check(label + ".header_size", got.__spec_header_size(), expected_size)
  i += 1

<< "bigint_mul1_5_source_spec: all checks passed"
