# The three-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7033

value = (1 << 128) + 37
check("three-limb square reopened dispatch", value * value, 7033)

<< "PASS BigInt sqr@3 reopen source seam"
