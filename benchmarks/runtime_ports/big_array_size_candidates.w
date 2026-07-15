# Benchmark-only source candidates for BigArray#size. Production
# core/big_array.w and the runtime IC stay untouched until a candidate clears
# both the unique-name and real-public-method gates.

use ../../core/big_array

+ BigArray
  # V1 is the literal source counterpart of w_big_array_size: load the signed
  # i64 header field and let the normal raw-i64 return boundary call w_int.
  # The explicit signed annotation matters because the view declaration uses
  # u64 for size/cap even though WBigArray stores int64_t fields in C.
  -> __w_big_array_size_v1
    n = $size ## i64
    n

  # V2 keeps the exact w_int representation but emits its overwhelmingly
  # common i48 arm in Tungsten. This avoids an out-of-line boxing call for
  # every realizable in-memory BigArray while retaining canonical one-limb
  # BigInts for both signed overflow directions.
  -> __w_big_array_size_v2
    n = $size ## i64
    if n >= -140_737_488_355_328 && n <= 140_737_488_355_327
      tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
      mask = 0xFFFFFFFFFFFF ## i64
      payload = (n & mask) ## i64
      return wvalue_from_bits((tag | payload) ## i64)
    ccall("w_int", n)
