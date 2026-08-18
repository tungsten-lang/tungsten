# The positive three-by-three add route preserves an open-world BigInt#+
# replacement at both the ordinary operator and stable source seam.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> +(other)(BigInt)
    3303

left = (1 << 128) + 37
right = (1 << 129) + 43
check("three-by-three reopened dispatch", left + right, 3303)
check("plus seam selects final definition",
      ccall("__w_bigint_plus_src", left, right), 3303)

<< "PASS BigInt add@3 reopen source seam"
