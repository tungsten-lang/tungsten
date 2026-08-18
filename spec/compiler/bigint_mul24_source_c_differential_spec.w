# Compiled-only direct native/C differential for the exact mul@24 leaf.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_mul24_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_mul24_raw($value ## i64, other$value ## i64)
    )

# Build exact-width positive operands directly so setup does not dominate the
# differential. The resulting objects have the same valid header and limb
# representation as public BigInt constructors.
fn __spec_make24(seed) (i64) i64
  result = ccall_nobox("w_bigint_alloc_hot32_raw") ## i64
  base = result & 140737488355327 ## i64
  raw_store_u8(base, 4, 24)
  raw_store_u8(base, 5, 0)
  raw_store_u8(base, 6, 0)
  raw_store_u8(base, 7, 0)
  j = 0 ## i64
  while j < 24
    x = (seed + (j + 1) * 0x9e3779b97f4a7c15) ## u64
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9 ## u64
    x = (x ^ (x >> 27)) * 0x94d049bb133111eb ## u64
    x = x ^ (x >> 31) ## u64
    if j == 23
      x = x | (1 << 63) ## u64
    k = 0 ## i64
    while k < 8
      raw_store_u8(base, 16 + j * 8 + k, (x >> (k * 8)) & 255)
      k += 1
    j += 1
  result

i = 0
while i < 100_000
  left = wvalue_from_bits(__spec_make24((i * 2 + 1) ## i64))
  right = wvalue_from_bits(__spec_make24((i * 2 + 2) ## i64))
  source = left.__spec_mul24_raw(right)
  c_oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt mul@24 direct source/C differential (100000)"
