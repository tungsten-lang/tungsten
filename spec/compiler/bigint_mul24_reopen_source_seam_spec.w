# The distinct positive twenty-four-by-twenty-four route preserves an
# open-world BigInt#* replacement at both ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    2424

left = (1 << 1472) + 37
right = (1 << 1473) + 43
check("twenty-four-by-twenty-four reopened dispatch", left * right, 2424)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul24_src", left, right), 2424)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 2424)

<< "PASS BigInt mul@24 reopen source seam"
