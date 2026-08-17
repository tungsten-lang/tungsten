# The distinct positive two-by-two route enters the ordinary BigInt#* source
# seam first, so an open-world replacement remains observable. Closed-world
# programs reject this reopen before lowering.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    2202

left = (1 << 64) + 37
right = (1 << 65) + 43
check("two-by-two reopened dispatch", left * right, 2202)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul2_src", left, right), 2202)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 2202)

<< "PASS BigInt mul@2 reopen source seam"
