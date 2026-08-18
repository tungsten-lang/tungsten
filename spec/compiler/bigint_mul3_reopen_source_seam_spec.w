# The distinct positive three-by-three route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    3303

left = (1 << 128) + 37
right = (1 << 129) + 43
check("three-by-three reopened dispatch", left * right, 3303)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul3_src", left, right), 3303)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 3303)

<< "PASS BigInt mul@3 reopen source seam"
