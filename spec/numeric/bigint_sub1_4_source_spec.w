# Positive four-limb BigInt minus positive one-limb BigInt.  On macOS ARM64
# this is the exact native Tungsten port of bigint_sub_ui_any's n==4 arm.

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

# Low limb subtraction needs no borrow.
plain = base ** 3 * 99 + word + 7
check_sub1("plain", plain, word, 4)

# Borrow dies in limb one.
borrow_one = base ** 3 * 99 + base * 42 + 7
check_sub1("borrow_one", borrow_one, word, 4)

# Borrow propagates through limbs one and two but dies below the top.
borrow_three = base ** 3 * 99 + 7
check_sub1("borrow_three", borrow_three, word, 4)

# A top limb of one is consumed, shrinking the result to three limbs.
full_word = base - 1
shrink = base ** 3 + 17
check_sub1("shrink", shrink, full_word, 3)

# Neighboring widths and sign shapes remain on their retained routes.
three = (1 << 191) + 29
five = (1 << 319) + 31
check("control.three", three - word, ccall("w_bigint_sub", three, word))
check("control.five", five - word, ccall("w_bigint_sub", five, word))
check("control.negative_rhs", plain - (0 - word),
      ccall("w_bigint_sub", plain, 0 - word))
check("control.negative_lhs", (0 - plain) - word,
      ccall("w_bigint_sub", 0 - plain, word))

<< "bigint_sub1_4_source_spec: all checks passed"
