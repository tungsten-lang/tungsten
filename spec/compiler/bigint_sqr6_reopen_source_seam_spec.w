# The six-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7066

value = (1 << 320) + 37
check("six-limb square reopened dispatch", value * value, 7066)

<< "PASS BigInt sqr@6 reopen source seam"
