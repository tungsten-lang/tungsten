# Positive seven-limb BigInt plus positive one-limb BigInt.  The literal C
# checkpoint is followed by a native carry-death split; every result remains
# checked against the retained C BigInt oracle.

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
plain = ((1 << 447) + 123) + base ** 5 * 97 + base ** 4 * 91 + base ** 3 * 83 + base * base * 77 + base * 99 + 7
check_add1("plain", plain, word, 7)

carry_one = ((1 << 447) + 17) + base ** 5 * 79 + base ** 4 * 73 + base ** 3 * 67 + base * base * 61 + base * 42 + (base - 5)
check_add1("carry_one", carry_one, word, 7)

carry_five = ((1 << 447) + 31) + base ** 5 * 44 + base ** 4 * (base - 1) + base ** 3 * (base - 1) + base * base * (base - 1) + base * (base - 1) + (base - 5)
check_add1("carry_five", carry_five, word, 7)

full_carry_word = 1 << 63
full_carry = base ** 7 - full_carry_word
check_add1("full_carry", full_carry, full_carry_word, 8)
check("full_carry.power", full_carry + full_carry_word, base ** 7)

six = (1 << 383) + 29
eight = (1 << 511) + 31
check("control.six", six + word, ccall("w_bigint_add", six, word))
check("control.eight", eight + word, ccall("w_bigint_add", eight, word))
check("control.negative_rhs", plain + (0 - word),
      ccall("w_bigint_add", plain, 0 - word))
check("control.negative_lhs", (0 - plain) + word,
      ccall("w_bigint_add", 0 - plain, word))

<< "bigint_add1_7_source_spec: all checks passed"
