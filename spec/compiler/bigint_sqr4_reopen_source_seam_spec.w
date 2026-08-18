# The four-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7044

value = (1 << 192) + 37
check("four-limb square reopened dispatch", value * value, 7044)

<< "PASS BigInt sqr@4 reopen source seam"
