# Compiled-only direct native/C differential for the exact mul@16 fixed leaf.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_mul16_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_mul16_raw($value ## i64, other$value ## i64)
    )

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  left = 0
  right = 0
  j = 0
  while j < 16
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    alimb = state
    state = (state * 2862933555777941757 + 3037000493) & mask64
    blimb = state
    if j == 15
      alimb = ((alimb ^ (alimb >> 23)) + i + 1) & mask64
      blimb = ((blimb ^ (blimb >> 29)) + i + 3) & mask64
      if alimb == 0
        alimb = 1
      if blimb == 0
        blimb = 1
    left += alimb << (j * 64)
    right += blimb << (j * 64)
    j += 1
  source = left.__spec_mul16_raw(right)
  c_oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt mul@16 direct source/C differential (100000)"
