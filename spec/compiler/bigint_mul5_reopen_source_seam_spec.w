# The distinct positive five-by-five route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    5505

left = (1 << 256) + 37
right = (1 << 257) + 43
check("five-by-five reopened dispatch", left * right, 5505)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul5_src", left, right), 5505)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 5505)

<< "PASS BigInt mul@5 reopen source seam"
