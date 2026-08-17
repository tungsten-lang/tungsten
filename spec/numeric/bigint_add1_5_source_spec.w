# Positive five-limb BigInt plus positive one-limb BigInt.  On macOS ARM64
# this is the native Tungsten port of bigint_add_ui_any's exact n==5 fixed
# arm; every result is checked against the retained C BigInt oracle.

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

# Low limb does not carry.
plain = ((1 << 319) + 123) + base ** 3 * 91 + base * base * 77 + base * 99 + 7
check_add1("plain", plain, word, 5)

# Carry leaves limb zero but dies at limb one.
carry_one = ((1 << 319) + 17) + base ** 3 * 73 + base * base * 61 + base * 42 + (base - 5)
check_add1("carry_one", carry_one, word, 5)

# Carry survives three limbs and dies at limb three.
carry_three = ((1 << 319) + 31) + base ** 3 * 44 + base * base * (base - 1) + base * (base - 1) + (base - 5)
check_add1("carry_three", carry_three, word, 5)

# Carry propagates through all five limbs.  The exact C path initially asks
# for cap five, then grows to cap six only after the fixed kernel reports
# carry-out.
full_carry_word = 1 << 63
full_carry = base ** 5 - full_carry_word
check_add1("full_carry", full_carry, full_carry_word, 6)
check("full_carry.power", full_carry + full_carry_word, base ** 5)

# Neighboring widths and sign shapes remain on their pre-existing routes.
four = (1 << 255) + 29
six = (1 << 383) + 31
check("control.four", four + word, ccall("w_bigint_add", four, word))
check("control.six", six + word, ccall("w_bigint_add", six, word))
check("control.negative_rhs", plain + (0 - word),
      ccall("w_bigint_add", plain, 0 - word))
check("control.negative_lhs", (0 - plain) + word,
      ccall("w_bigint_add", 0 - plain, word))

<< "bigint_add1_5_source_spec: all checks passed"
