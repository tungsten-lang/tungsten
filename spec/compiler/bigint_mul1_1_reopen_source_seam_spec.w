# The exact positive one-limb multiplication seam must preserve ordinary
# open-world BigInt#* replacement. Closed-world programs reject this reopen
# before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7009

a = ccall("w_bigint_from_dec_str", "9223372036854775901")
b = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("ordinary reopened dispatch", a * b, 7009)
check("narrow seam selects final definition",
      ccall("__w_bigint_mul1_1_src", a, b), 7009)

<< "PASS BigInt mul1@1 reopen source seam"
