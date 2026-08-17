# The one-limb square route enters the ordinary BigInt#* source seam first,
# so an open-world replacement remains observable. Closed-world programs
# reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7013

value = ccall("w_bigint_from_dec_str", "9223372036854775901")
check("one-limb square reopened dispatch", value * value, 7013)

<< "PASS BigInt sqr@1 reopen source seam"
