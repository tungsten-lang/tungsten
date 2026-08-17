# The distinct positive seven-by-seven route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7707

left = (1 << 384) + 37
right = (1 << 385) + 43
check("seven-by-seven reopened dispatch", left * right, 7707)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul7_src", left, right), 7707)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 7707)

<< "PASS BigInt mul@7 reopen source seam"
