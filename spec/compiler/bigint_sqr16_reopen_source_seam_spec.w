# The sixteen-limb square route preserves an open-world BigInt#* replacement.

-> check(label, got, expected)
  if got != expected
    << "FAIL [label]: got=[got] expected=[expected]"
    exit 1

+ BigInt
  -> *(other)(BigInt)
    16161

value = (1 << 960) + 37
check("sixteen-limb square reopened dispatch", value * value, 16161)
check("dedicated seam selects final definition",
      ccall("__w_bigint_sqr16_src", value, value), 16161)
check("times seam selects final definition",
      ccall("__w_bigint_times_src", value, value), 16161)

<< "PASS BigInt sqr@16 reopen source seam"
