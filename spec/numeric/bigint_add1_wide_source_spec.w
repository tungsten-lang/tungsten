# Positive 9..4096-limb BigInt plus positive one-limb BigInt.  On macOS ARM64
# this is the exact native Tungsten port of bigint_add_word_into's wide arm.

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
full_word = base - 1

# Ordinary copy-tail path at the first wide width.
plain9 = base ** 8 * 99 + 37
check_add1("plain9", plain9, word, 9)

# Carry dies in limb one, then the tuned tail copies limbs 2..15.
carry1_16 = base ** 15 * 99 + base * 42 + full_word
check_add1("carry1_16", carry1_16, word, 16)

# Carry traverses every lower limb and dies at the top without growth.
carry_top64 = base ** 63 * 99 + (base ** 63 - 1)
check_add1("carry_top64", carry_top64, word, 64)

# Carry runs off the top and exercises the exact grow/reallocate finisher.
grow16 = base ** 16 - 1
check_add1("grow16", grow16, word, 17)

# Cross-width differential coverage for copied tails, top carry, and growth.
widths = [9, 12, 16, 24, 32, 48, 64, 128, 256]
wi = 0
while wi < widths.size
  n = widths[wi]
  high = base ** (n - 1)
  label = n.to_s()
  check_add1("sweep.copy." + label, high * 99 + 37, word, n)
  check_add1(
    "sweep.top." + label,
    high * 99 + (high - 1), word, n
  )
  check_add1("sweep.grow." + label, base ** n - 1, word, n + 1)
  wi += 1

# Adjacent fixed and sign shapes remain on their retained routes.
fixed8 = (1 << 511) + 29
check("control.fixed8", fixed8 + word, ccall("w_bigint_add", fixed8, word))
check("control.negative_rhs", plain9 + (0 - word),
      ccall("w_bigint_add", plain9, 0 - word))
check("control.negative_lhs", (0 - plain9) + word,
      ccall("w_bigint_add", 0 - plain9, word))

<< "bigint_add1_wide_source_spec: all checks passed"
