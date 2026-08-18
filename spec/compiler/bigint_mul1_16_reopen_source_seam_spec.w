# The positive 16-by-1 source seam must preserve open-world BigInt#* dispatch.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    1601

wide = ccall("w_bigint_from_dec_str", "9745314011399999080353382387875188310876226857595007526867906457212948690766426102465615065882010259225304916231408668183459169865203094046577987296312653419531277699956473029870789655490053648352799593479218378873685597925394874945746363615468965612827738803104277547081828589991914111013")
word = ccall("w_bigint_from_dec_str", "9223372036854775819")
check("wide receiver reopened dispatch", wide * word, 1601)
check("word receiver reopened dispatch", word * wide, 1601)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", wide, word), 1601)

<< "PASS BigInt mul1@16 reopen source seam"
