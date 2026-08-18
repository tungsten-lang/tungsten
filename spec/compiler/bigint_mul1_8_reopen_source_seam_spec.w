# The positive 8-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    7069

wide = ccall("w_bigint_from_dec_str", "726838724295606890549323807888004534353641360687318060281490199180639288113397923326191050713763565560762521606266177933534601628614657")
word = ccall("w_bigint_from_dec_str", "9223372036854775825")
check("wide receiver reopened dispatch", wide * word, 7069)
check("word receiver reopened dispatch", word * wide, 7069)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 7069)

<< "PASS BigInt mul1@8 reopen source seam"
