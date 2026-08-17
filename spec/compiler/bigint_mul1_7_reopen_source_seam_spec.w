# The positive 7-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7059

wide = ccall("w_bigint_from_dec_str", "39402006196394479212279040100143613805079739270465446667948293404245721771497210611414266254884915640806627990306817")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7059)
check("word receiver reopened dispatch", word * wide, 7059)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7059)

<< "PASS BigInt mul1@7 reopen source seam"
