# The narrow positive two-by-one-limb subtraction seam must preserve ordinary
# open-world BigInt#- replacement, just like the complete minus seam.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> -(other)(BigInt)
    7005

a = ccall("w_bigint_from_dec_str", "18446744073709551633")
b = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("ordinary reopened dispatch", a - b, 7005)
check("narrow seam selects final definition",
      ccall("__w_bigint_sub1_2_src", a, b), 7005)

<< "PASS BigInt sub1@2 reopen source seam"
