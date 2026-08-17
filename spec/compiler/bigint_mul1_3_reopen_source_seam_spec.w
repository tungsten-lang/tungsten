# The newly admitted positive 3-by-1 multiplication shape must preserve an
# ordinary open-world BigInt#* replacement and its original receiver order.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7019

wide = ccall("w_bigint_from_dec_str", "340282366920938463463374607431768211457")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7019)
check("word receiver reopened dispatch", word * wide, 7019)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7019)

<< "PASS BigInt mul1@3 reopen source seam"
