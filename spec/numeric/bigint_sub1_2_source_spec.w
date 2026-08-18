# Positive two-limb BigInt minus positive one-limb BigInt.  On macOS ARM64
# this is the exact native Tungsten port of bigint_sub_ui_any's n==2 arm.

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
plain = base * 99 + word + 7
check_sub1("plain", plain, word, 2)

# Borrow leaves the two-limb magnitude intact.
borrow_one = base * 99 + 7
check_sub1("borrow_one", borrow_one, word, 2)

# Borrow consumes a top limb of one and shrinks to a boxed one-limb result.
full_word = base - 1
shrink_boxed = base + (1 << 63)
check_sub1("shrink_boxed", shrink_boxed, full_word, 1)

# The same shrink path demotes an i48 result rather than retaining the box.
i48_max = (1 << 47) - 1
check("shrink_i48_edge", (base + i48_max - 1) - full_word, i48_max)
check("shrink_to_i48", (base + 16) - full_word, 17)

# Neighboring widths and sign shapes remain on their retained routes.
one = (1 << 63) + 29
three = (1 << 191) + 31
check("control.one", one - word, ccall("w_bigint_sub", one, word))
check("control.three", three - word, ccall("w_bigint_sub", three, word))
check("control.negative_rhs", plain - (0 - word),
      ccall("w_bigint_sub", plain, 0 - word))
check("control.negative_lhs", (0 - plain) - word,
      ccall("w_bigint_sub", 0 - plain, word))

<< "bigint_sub1_2_source_spec: all checks passed"
