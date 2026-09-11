# The positive equal-width add@4/8/16 routes preserve an open-world BigInt#+
# replacement at both the ordinary operator and stable source seam.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> +(other)(BigInt)
    3304

four_left = (1 << 192) + 37
four_right = (1 << 193) + 43
eight_left = (1 << 448) + 37
eight_right = (1 << 449) + 43
sixteen_left = (1 << 960) + 37
sixteen_right = (1 << 961) + 43
check("four-by-four reopened dispatch", four_left + four_right, 3304)
check("eight-by-eight reopened dispatch", eight_left + eight_right, 3304)
check("sixteen-by-sixteen reopened dispatch", sixteen_left + sixteen_right, 3304)
check("plus seam selects final definition (4)",
      ccall("__w_bigint_plus_src", four_left, four_right), 3304)
check("plus seam selects final definition (8)",
      ccall("__w_bigint_plus_src", eight_left, eight_right), 3304)
check("plus seam selects final definition (16)",
      ccall("__w_bigint_plus_src", sixteen_left, sixteen_right), 3304)

<< "PASS BigInt add@4/8/16 reopen source seam"
