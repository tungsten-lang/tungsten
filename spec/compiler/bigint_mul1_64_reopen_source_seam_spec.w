# The positive 64-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    6401

wide = 1 << 4032
word = (1 << 63) + 29
check("wide receiver reopened dispatch", wide * word, 6401)
check("word receiver reopened dispatch", word * wide, 6401)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 6401)

<< "PASS BigInt mul1@64 reopen source seam"
