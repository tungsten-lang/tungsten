# The positive 32-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    3201

wide = 1 << 1984
word = (1 << 63) + 23
check("wide receiver reopened dispatch", wide * word, 3201)
check("word receiver reopened dispatch", word * wide, 3201)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 3201)

<< "PASS BigInt mul1@32 reopen source seam"
