# The positive 5-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7039

wide = ccall("w_bigint_from_dec_str", "115792089237316195423570985008687907853269984665640564039457584007913129639937")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7039)
check("word receiver reopened dispatch", word * wide, 7039)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7039)

<< "PASS BigInt mul1@5 reopen source seam"
