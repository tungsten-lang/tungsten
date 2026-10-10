# Int#popcount / Int#bit_count: ones in the magnitude (Python int.bit_count).
# Must agree on every engine and across the Int/BigInt boundary.

-> check(name, got, want)
  if got != want
    << "FAIL [name]: got=[got] want=[want]"
    exit(1)

-> erased_popcount(value)
  value.popcount

check("zero", 0.popcount, 0)
check("one", 1.popcount, 1)
check("byte", 255.popcount, 8)
check("pow2", 256.popcount, 1)
check("negative uses magnitude", (-255).popcount, 8)
check("alias", 255.bit_count, 8)
check("mixed", 0b101101.popcount, 4)
check("i32 edge", 4294967295.popcount, 32)
check("chunk boundary", 4294967296.popcount, 1)
check("chunk boundary +1", 4294967297.popcount, 2)
check("2^100 - 1", (2 ** 100 - 1).popcount, 100)
check("2^100", (2 ** 100).popcount, 1)
check("big mixed", (2 ** 64 + 2 ** 40 + 1).bit_count, 3)
check("big negative", (-(2 ** 70 + 1)).popcount, 2)
check("erased receiver", erased_popcount(1023), 10)
check("erased big", erased_popcount(2 ** 80 - 1), 80)
<< "ok"
