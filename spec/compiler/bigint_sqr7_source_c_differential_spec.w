# Compiled-only direct native/C differential for the exact sqr@7 leaf. Run
# with TUNGSTEN_BIGINT_SRC_OPS=0: the public exact boundary is then pinned to
# C, while this method still calls the strong native raw worker explicitly.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_sqr7_raw
    wvalue_from_bits(__bigint_sqr7_raw($value ## i64, $value ## i64))

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  low = state
  limb1 = ((state ^ (state >> 23)) + i + 1) & mask64
  limb2 = ((limb1 ^ (limb1 >> 29)) + i + 3) & mask64
  limb3 = ((limb2 ^ (limb2 >> 31)) + i + 5) & mask64
  limb4 = ((limb3 ^ (limb3 >> 27)) + i + 7) & mask64
  limb5 = ((limb4 ^ (limb4 >> 25)) + i + 9) & mask64
  high = ((limb5 ^ (limb5 >> 21)) + i + 11) & mask64
  if high == 0
    high = 1
  value = (high << 384) + (limb5 << 320) + (limb4 << 256) + (limb3 << 192) + (limb2 << 128) + (limb1 << 64) + low
  if (i & 1) == 1
    value = 0 - value
  source = value.__spec_sqr7_raw()
  c_oracle = ccall("w_bigint_mul_builtin_exact", value, value)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt sqr@7 direct source/C differential (100000)"
