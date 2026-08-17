# The seven-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7077

value = (1 << 384) + 37
check("seven-limb square reopened dispatch", value * value, 7077)

<< "PASS BigInt sqr@7 reopen source seam"
