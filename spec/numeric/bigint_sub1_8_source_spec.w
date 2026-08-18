# Positive eight-limb BigInt minus positive one-limb BigInt.  On macOS ARM64
# this is the exact native Tungsten port of bigint_sub_ui_any's n==8 arm.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_sub1(name, a, b, expected_size)
  got = a - b
  want = ccall("w_bigint_sub", a, b)
  check(name + ".value", got, want)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".roundtrip", got + b, a)

base = 1 << 64
word = (1 << 63) + 11
plain = base ** 7 * 99 + word + 7
check_sub1("plain", plain, word, 8)
borrow_one = base ** 7 * 99 + base * 42 + 7
check_sub1("borrow_one", borrow_one, word, 8)
borrow_seven = base ** 7 * 99 + 7
check_sub1("borrow_seven", borrow_seven, word, 8)
full_word = base - 1
shrink = base ** 7 + 17
check_sub1("shrink", shrink, full_word, 7)

seven = (1 << 447) + 29
nine = (1 << 575) + 31
check("control.seven", seven - word, ccall("w_bigint_sub", seven, word))
check("control.nine", nine - word, ccall("w_bigint_sub", nine, word))
check("control.negative_rhs", plain - (0 - word),
      ccall("w_bigint_sub", plain, 0 - word))
check("control.negative_lhs", (0 - plain) - word,
      ccall("w_bigint_sub", 0 - plain, word))

<< "bigint_sub1_8_source_spec: all checks passed"
