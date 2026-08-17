# Distinct positive one-limb BigInt times positive one-limb BigInt. On macOS
# ARM64 this is the exact native Tungsten port of bigint_mul_positive_11;
# representation finishing remains the shared C boundary.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_mul1(name, a, b, expected, expected_size)
  got = a * b
  check(name + ".value", got.to_s(), expected)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", b * a, got)
  check(name + ".roundtrip", got / b, a)

base = 1 << 64
heap = 1 << 48

# Canonical positive heap one-limb inputs always produce a two-limb product.
check_mul1("minimum_heap_pair", heap, heap + 1,
           "79228162514264619068520660992", 2)
check_mul1("ordinary", heap + 17, (1 << 63) + 29,
           "2596148429267570619752649020408301", 2)
check_mul1("maximum_pair", base - 1, base - 3,
           "340282366920938463389587631136930004995", 2)

# Pointer-identical squaring and neighboring sign/width shapes remain on C.
square = heap + 37
check("control.square", (square * square).to_s(),
      "79228162514285166741820540249")
check("control.negative_rhs", ((heap + 17) * (0 - heap - 29)).to_s(),
      "-79228162514277285442472641005")
check("control.negative_lhs", ((0 - heap - 17) * (heap + 29)).to_s(),
      "-79228162514277285442472641005")
two_limb = base + 37
check("control.two_limb", (two_limb * (heap + 3)).to_s(),
      "5192296858534882979177291596169327")

<< "bigint_mul1_1_source_spec: all checks passed"
