# Compiled-only direct native/C differential for the exact mul@2 leaf. Run
# with TUNGSTEN_BIGINT_SRC_OPS=0: the public boundary is pinned to C, while
# this method still calls the strong native raw worker explicitly.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_mul2_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_mul2_raw($value ## i64, other$value ## i64)
    )

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  alow = state
  ahigh = ((state ^ (state >> 23)) + i + 1) & mask64
  if ahigh == 0
    ahigh = 1
  state = (state * 2862933555777941757 + 3037000493) & mask64
  blow = state
  bhigh = ((state ^ (state >> 29)) + i + 3) & mask64
  if bhigh == 0
    bhigh = 1
  left = (ahigh << 64) + alow
  right = (bhigh << 64) + blow
  source = left.__spec_mul2_raw(right)
  c_oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt mul@2 direct source/C differential (100000)"
