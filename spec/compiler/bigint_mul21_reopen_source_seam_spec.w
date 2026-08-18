# The distinct positive twenty-one-by-twenty-one route preserves an open-world
# BigInt#* replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    2121

left = (1 << 1280) + 37
right = (1 << 1281) + 43
check("twenty-one-by-twenty-one reopened dispatch", left * right, 2121)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul21_src", left, right), 2121)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 2121)

<< "PASS BigInt mul@21 reopen source seam"
