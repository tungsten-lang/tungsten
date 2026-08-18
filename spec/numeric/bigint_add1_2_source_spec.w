# Positive two-limb BigInt plus positive one-limb BigInt.  On macOS ARM64
# this is the native Tungsten port of bigint_add_ui_any's exact n==2 fixed
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
plain = (1 << 127) + base * 99 + 7
check_add1("plain", plain, word, 2)

# Carry leaves limb zero but dies at limb one.
carry_one = (1 << 127) + base * 42 + (base - 5)
check_add1("carry_one", carry_one, word, 2)

# Carry propagates through both limbs and grows the result from two to three.
full_carry_word = 1 << 63
full_carry = base ** 2 - full_carry_word
check_add1("full_carry", full_carry, full_carry_word, 3)
check("full_carry.power", full_carry + full_carry_word, base ** 2)

# Neighboring widths and sign shapes remain on their pre-existing routes.
one = (1 << 63) + 29
three = (1 << 191) + 31
check("control.one", one + word, ccall("w_bigint_add", one, word))
check("control.three", three + word, ccall("w_bigint_add", three, word))
check("control.negative_rhs", plain + (0 - word),
      ccall("w_bigint_add", plain, 0 - word))
check("control.negative_lhs", (0 - plain) + word,
      ccall("w_bigint_add", 0 - plain, word))

<< "bigint_add1_2_source_spec: all checks passed"
