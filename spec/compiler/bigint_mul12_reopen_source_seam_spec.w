# The distinct positive twelve-by-twelve route preserves an open-world
# BigInt#* replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    1212

left = (1 << 704) + 37
right = (1 << 705) + 43
check("twelve-by-twelve reopened dispatch", left * right, 1212)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul12_src", left, right), 1212)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 1212)

<< "PASS BigInt mul@12 reopen source seam"
