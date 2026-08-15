# An explicit machine-int result type applies to every link in a nested
# expression.  A boxed intermediate here turns the raw WValue tag into a
# BigInt and then exposes the BigInt pointer as the result.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got=" + got.to_s() + " want=" + want.to_s()
    exit(1)

-> inline_negative_digit_bits(digit) (i64) i64
  string_tag = -1_970_324_836_974_592 ## i64
  length = 2 ## i64
  (string_tag | (length << 1) | (45 << 4) | ((digit + 48) << 12)) ## i64

text = wvalue_from_bits(inline_negative_digit_bits(7))
check("nested raw bit expression", text, "-7")
check("negative Int#to_s", (0 - 32).to_s(), "-32")

<< "PASS raw machine expression context"
