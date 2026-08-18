# The five-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7055

value = (1 << 256) + 37
check("five-limb square reopened dispatch", value * value, 7055)

<< "PASS BigInt sqr@5 reopen source seam"
