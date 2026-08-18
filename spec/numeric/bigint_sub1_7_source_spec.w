# Positive seven-limb BigInt minus positive one-limb BigInt.  On macOS ARM64
# this is the exact native Tungsten port of bigint_sub_ui_any's n==7 arm.

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
plain = base ** 6 * 99 + word + 7
check_sub1("plain", plain, word, 7)
borrow_one = base ** 6 * 99 + base * 42 + 7
check_sub1("borrow_one", borrow_one, word, 7)
borrow_six = base ** 6 * 99 + 7
check_sub1("borrow_six", borrow_six, word, 7)
full_word = base - 1
shrink = base ** 6 + 17
check_sub1("shrink", shrink, full_word, 6)

six = (1 << 383) + 29
eight = (1 << 511) + 31
check("control.six", six - word, ccall("w_bigint_sub", six, word))
check("control.eight", eight - word, ccall("w_bigint_sub", eight, word))
check("control.negative_rhs", plain - (0 - word),
      ccall("w_bigint_sub", plain, 0 - word))
check("control.negative_lhs", (0 - plain) - word,
      ccall("w_bigint_sub", 0 - plain, word))

<< "bigint_sub1_7_source_spec: all checks passed"
