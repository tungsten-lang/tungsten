# The distinct positive four-by-four route preserves an open-world BigInt#*
# replacement at both the ordinary and dedicated source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    4404

left = (1 << 192) + 37
right = (1 << 193) + 43
check("four-by-four reopened dispatch", left * right, 4404)
check("dedicated seam selects final definition",
      ccall("__w_bigint_mul4_src", left, right), 4404)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", left, right), 4404)

<< "PASS BigInt mul@4 reopen source seam"
