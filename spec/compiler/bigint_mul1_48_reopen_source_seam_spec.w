# The positive 48-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    4801

wide = 1 << 3008
word = (1 << 63) + 29
check("wide receiver reopened dispatch", wide * word, 4801)
check("word receiver reopened dispatch", word * wide, 4801)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 4801)

<< "PASS BigInt mul1@48 reopen source seam"
