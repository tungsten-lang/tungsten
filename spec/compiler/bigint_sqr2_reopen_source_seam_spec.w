# The two-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7023

value = (1 << 64) + 37
check("two-limb square reopened dispatch", value * value, 7023)

<< "PASS BigInt sqr@2 reopen source seam"
