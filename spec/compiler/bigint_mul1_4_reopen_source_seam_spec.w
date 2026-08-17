# The newly admitted positive 4-by-1 multiplication shape must preserve an
# ordinary open-world BigInt#* replacement and its original receiver order.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7029

wide = ccall("w_bigint_from_dec_str", "6277101735386680763835789423207666416102355444464034512897")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7029)
check("word receiver reopened dispatch", word * wide, 7029)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7029)

<< "PASS BigInt mul1@4 reopen source seam"
