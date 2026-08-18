# The distinct positive sixteen-by-sixteen route preserves an open-world
# BigInt#* replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    1616

left = (1 << 960) + 37
right = (1 << 961) + 43
check("sixteen-by-sixteen reopened dispatch", left * right, 1616)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul16_src", left, right), 1616)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 1616)

<< "PASS BigInt mul@16 reopen source seam"
