# BigInt#to_s — pins the source shim over the exported w_bigint_to_s
# boundary (IC row 0 retired). The D&C decimal writer and base-N chunk
# loop stay in the runtime; statically :int-typed sites keep the
# compiler's w_int_to_s intercept and print/interpolation paths use
# w_to_s directly, so all three routes must agree.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

a = (1 << 100) + 12345
check("decimal", a.to_s(), "1267650600228229401496703217721")
check("negative", (0 - a).to_s(), "-1267650600228229401496703217721")

# Interpolation and explicit to_s must agree (different routes)
check("interp_agrees", "[a]", a.to_s())

# Base conversions
check("hex", (255 + (1 << 64)).to_s(16), "100000000000000ff")
check("bin", (5 + (1 << 65)).to_s(2), "100000000000000000000000000000000000000000000000000000000000000101")
check("b36", ((1 << 80) + 1).to_s(36), "5gv2rma270x9hhj5")

# Multi-limb D&C path (round-trip through the string parser)
big = 10 ** 500 + 987654321
check("dnc_roundtrip", big.to_s().to_i, big)
check("dnc_len", big.to_s().size(), 501)

# One-limb heap values
p1 = (1 << 60) + 7
check("one_limb", p1.to_s(), "1152921504606846983")

<< "bigint_to_s_spec: all checks passed"
