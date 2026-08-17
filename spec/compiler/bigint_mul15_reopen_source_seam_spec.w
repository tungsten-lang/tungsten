# The distinct positive fifteen-by-fifteen route preserves an open-world
# BigInt#* replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    1515

left = (1 << 896) + 37
right = (1 << 897) + 43
check("fifteen-by-fifteen reopened dispatch", left * right, 1515)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul15_src", left, right), 1515)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 1515)

<< "PASS BigInt mul@15 reopen source seam"
