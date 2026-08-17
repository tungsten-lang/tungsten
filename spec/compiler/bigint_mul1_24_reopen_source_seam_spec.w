# The positive 24-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    2401

wide = 1 << 1472
word = (1 << 63) + 19
check("wide receiver reopened dispatch", wide * word, 2401)
check("word receiver reopened dispatch", word * wide, 2401)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 2401)

<< "PASS BigInt mul1@24 reopen source seam"
