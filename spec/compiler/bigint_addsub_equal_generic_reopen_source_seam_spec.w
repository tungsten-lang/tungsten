# The generic equal-width add/sub routes preserve open-world BigInt#+ and
# BigInt#- replacements at both the ordinary operators and the source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> +(other)(BigInt)
    3307

  -> -(other)(BigInt)
    3308

widths = [5, 7, 12, 20, 23]
i = 0
while i < widths.size
  width = widths[i]
  left = (1 << (64 * width - 1)) + 37
  right = (1 << (64 * width - 2)) + 43
  check("add reopened dispatch at " + width.to_s(), left + right, 3307)
  check("sub reopened dispatch at " + width.to_s(), left - right, 3308)
  check("plus seam at " + width.to_s(),
        ccall("__w_bigint_plus_src", left, right), 3307)
  check("minus seam at " + width.to_s(),
        ccall("__w_bigint_minus_src", left, right), 3308)
  i += 1

<< "PASS BigInt generic equal-width reopen source seams"
