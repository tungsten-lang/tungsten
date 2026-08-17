# Positive six-limb BigInt plus positive one-limb BigInt.  On macOS ARM64
# this is the literal native Tungsten port of C's n==6 fixed add-word arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_add1(name, a, b, expected_size)
  got = a + b
  want = ccall("w_bigint_add", a, b)
  check(name + ".value", got, want)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".roundtrip", got - b, a)

base = 1 << 64
word = (1 << 63) + 11
plain = ((1 << 383) + 123) + base ** 4 * 91 + base ** 3 * 83 + base * base * 77 + base * 99 + 7
check_add1("plain", plain, word, 6)

carry_one = ((1 << 383) + 17) + base ** 4 * 73 + base ** 3 * 67 + base * base * 61 + base * 42 + (base - 5)
check_add1("carry_one", carry_one, word, 6)

carry_four = ((1 << 383) + 31) + base ** 4 * 44 + base ** 3 * (base - 1) + base * base * (base - 1) + base * (base - 1) + (base - 5)
check_add1("carry_four", carry_four, word, 6)

full_carry_word = 1 << 63
full_carry = base ** 6 - full_carry_word
check_add1("full_carry", full_carry, full_carry_word, 7)
check("full_carry.power", full_carry + full_carry_word, base ** 6)

five = (1 << 319) + 29
seven = (1 << 447) + 31
check("control.five", five + word, ccall("w_bigint_add", five, word))
check("control.seven", seven + word, ccall("w_bigint_add", seven, word))
check("control.negative_rhs", plain + (0 - word),
      ccall("w_bigint_add", plain, 0 - word))
check("control.negative_lhs", (0 - plain) + word,
      ccall("w_bigint_add", 0 - plain, word))

<< "bigint_add1_6_source_spec: all checks passed"
