# The distinct positive eight-by-eight route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    8808

left = (1 << 448) + 37
right = (1 << 449) + 43
check("eight-by-eight reopened dispatch", left * right, 8808)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul8_src", left, right), 8808)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 8808)

<< "PASS BigInt mul@8 reopen source seam"
