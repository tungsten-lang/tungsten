# Positive one-limb BigInt plus positive one-limb BigInt. On macOS ARM64 this
# is the exact native Tungsten port of bigint_add_one_limb_magnitudes' same-
# sign arm; representation finishing remains the shared C boundary.

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
heap = 1 << 48

# No carry: the result remains a positive one-limb heap BigInt.
check_add1("no_carry", heap + 17, heap + 29, 1)

# Carry: two one-limb inputs grow to the exact two-limb representation.
check_add1("carry", base - 1, base - 7, 2)
check_add1("carry_low_zero", base - heap, heap, 2)

# Boundary values around the source gate.
check_add1("minimum_heap_pair", heap, heap, 1)
check_add1("maximum_pair", base - 1, base - 1, 2)

# Neighboring widths and sign shapes remain byte-identical to the C oracle.
two_limb = base + 37
check("control.two_limb", two_limb + (heap + 3),
      ccall("w_bigint_add", two_limb, heap + 3))
check("control.negative_rhs", (heap + 17) + (0 - heap - 29),
      ccall("w_bigint_add", heap + 17, 0 - heap - 29))
check("control.negative_lhs", (0 - heap - 17) + (heap + 29),
      ccall("w_bigint_add", 0 - heap - 17, heap + 29))

<< "bigint_add1_1_source_spec: all checks passed"
