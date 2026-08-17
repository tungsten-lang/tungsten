# Positive 9..4096-limb BigInt minus positive one-limb BigInt.  On macOS
# ARM64 this is the exact native Tungsten port of bigint_sub_word_into's wide
# prefix/ripple/copy/shrink route.

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

# Ordinary copy-tail path at the first wide width.
plain9 = base ** 8 * 99 + word + 7
check_sub1("plain9", plain9, word, 9)

# Borrow dies in limb one, then the tuned tail copies limbs 2..15.
borrow1_16 = base ** 15 * 99 + base * 42 + 7
check_sub1("borrow1_16", borrow1_16, word, 16)

# Borrow propagates through every lower limb before dying at the top.
borrow63_64 = base ** 63 * 99 + 7
check_sub1("borrow63_64", borrow63_64, word, 64)

# The top limb is consumed and normalization shrinks by exactly one limb.
full_word = base - 1
shrink16 = base ** 15 + 17
check_sub1("shrink16", shrink16, full_word, 15)

# Cross-width differential coverage for the three wide outcomes: a copied
# suffix after limb one, a borrow reaching the top, and top-limb shrink.
widths = [9, 12, 16, 24, 32, 48, 64, 128, 256]
wi = 0
while wi < widths.size
  n = widths[wi]
  high = base ** (n - 1)
  label = n.to_s()
  check_sub1("sweep.copy." + label, high * 99 + base * 42 + 7, word, n)
  check_sub1("sweep.ripple." + label, high * 99 + 7, word, n)
  check_sub1("sweep.shrink." + label, high + 17, full_word, n - 1)
  wi += 1

# Adjacent fixed and sign shapes remain on their retained routes.
fixed8 = (1 << 511) + 29
check("control.fixed8", fixed8 - word, ccall("w_bigint_sub", fixed8, word))
check("control.negative_rhs", plain9 - (0 - word),
      ccall("w_bigint_sub", plain9, 0 - word))
check("control.negative_lhs", (0 - plain9) - word,
      ccall("w_bigint_sub", 0 - plain9, word))

<< "bigint_sub1_wide_source_spec: all checks passed"
