# The distinct positive six-by-six route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    6606

left = (1 << 320) + 37
right = (1 << 321) + 43
check("six-by-six reopened dispatch", left * right, 6606)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul6_src", left, right), 6606)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 6606)

<< "PASS BigInt mul@6 reopen source seam"
