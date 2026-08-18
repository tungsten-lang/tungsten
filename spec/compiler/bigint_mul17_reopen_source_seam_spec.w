# The distinct positive seventeen-by-seventeen route preserves an open-world
# BigInt#* replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    1717

left = (1 << 1024) + 37
right = (1 << 1025) + 43
check("seventeen-by-seventeen reopened dispatch", left * right, 1717)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul17_src", left, right), 1717)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 1717)

<< "PASS BigInt mul@17 reopen source seam"
