# Positive eight-limb BigInt plus positive one-limb BigInt.  On macOS ARM64
# this is the literal native Tungsten port of C's carry-death n==8 arm.

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
plain = ((1 << 511) + 123) + base ** 6 * 101 + base ** 5 * 97 + base ** 4 * 91 + base ** 3 * 83 + base * base * 77 + base * 99 + 7
check_add1("plain", plain, word, 8)

# Carry dies by limb one and therefore uses C's common carry-death arm.
carry_one = ((1 << 511) + 17) + base ** 6 * 89 + base ** 5 * 79 + base ** 4 * 73 + base ** 3 * 67 + base * base * 61 + base * 42 + (base - 5)
check_add1("carry_one", carry_one, word, 8)

# Carry survives limb one, enters the rare full chain, and dies at limb two.
carry_two = ((1 << 511) + 19) + base ** 6 * 83 + base ** 5 * 79 + base ** 4 * 73 + base ** 3 * 67 + base * base * 42 + base * (base - 1) + (base - 5)
check_add1("carry_two", carry_two, word, 8)

# Carry propagates through all eight limbs and grows to nine.
full_carry_word = 1 << 63
full_carry = base ** 8 - full_carry_word
check_add1("full_carry", full_carry, full_carry_word, 9)
check("full_carry.power", full_carry + full_carry_word, base ** 8)

seven = (1 << 447) + 29
nine = (1 << 575) + 31
check("control.seven", seven + word, ccall("w_bigint_add", seven, word))
check("control.nine", nine + word, ccall("w_bigint_add", nine, word))
check("control.negative_rhs", plain + (0 - word),
      ccall("w_bigint_add", plain, 0 - word))
check("control.negative_lhs", (0 - plain) + word,
      ccall("w_bigint_add", 0 - plain, word))

<< "bigint_add1_8_source_spec: all checks passed"
