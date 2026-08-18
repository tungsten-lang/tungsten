# The positive 6-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7049

wide = ccall("w_bigint_from_dec_str", "2135987035920910082395021706169552114602704522356652769947041607822219725780640550022962086936577")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7049)
check("word receiver reopened dispatch", word * wide, 7049)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7049)

<< "PASS BigInt mul1@6 reopen source seam"
