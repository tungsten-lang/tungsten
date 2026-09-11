# The positive equal-width add@2/24 and sub@2/3/4/8/16/24 routes preserve
# open-world BigInt#+ and BigInt#- replacements at both the ordinary
# operators and the stable source seams.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> +(other)(BigInt)
    3305

  -> -(other)(BigInt)
    3306

widths = [2, 3, 4, 8, 16, 24]
i = 0
while i < widths.size
  width = widths[i]
  left = (1 << (64 * width - 1)) + 37
  right = (1 << (64 * width - 2)) + 43
  check("add reopened dispatch at " + width.to_s(), left + right, 3305)
  check("sub reopened dispatch at " + width.to_s(), left - right, 3306)
  check("plus seam at " + width.to_s(),
        ccall("__w_bigint_plus_src", left, right), 3305)
  check("minus seam at " + width.to_s(),
        ccall("__w_bigint_minus_src", left, right), 3306)
  i += 1

<< "PASS BigInt add/sub equal-width reopen source seams"
