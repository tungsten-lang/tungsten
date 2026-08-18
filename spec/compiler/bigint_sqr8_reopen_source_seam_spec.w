# The eight-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7088

value = (1 << 448) + 37
check("eight-limb square reopened dispatch", value * value, 7088)

<< "PASS BigInt sqr@8 reopen source seam"
