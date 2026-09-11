# Compiled-only direct native/C differential for the exact add@4, add@8, and
# add@16 leaves. The public C boundary stays available as an independent
# oracle.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_add4_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_add4_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_add8_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_add8_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_add16_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_add16_equal_raw($value ## i64, other$value ## i64)
    )

-> pair_at(width, i, state)
  mask64 = (1 << 64) - 1
  left = 0
  right = 0
  k = 0
  while k < width
    state = (state * 6364136223846793005 + 1442695040888963407) & mask64
    limb = state
    if k == width - 1 && limb == 0
      limb = 1
    left = left + (limb << (64 * k))
    state = (state * 2862933555777941757 + 3037000493) & mask64
    limb = (state ^ (state >> 23)) & mask64
    if k == width - 1 && limb == 0
      limb = 1
    right = right + (limb << (64 * k))
    k += 1
  [left, right, state]

-> run_width(width, count)
  state = 0x9e3779b97f4a7c15 + width
  i = 0
  while i < count
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    source = nil
    if width == 4
      source = left.__spec_add4_equal_raw(right)
    if width == 8
      source = left.__spec_add8_equal_raw(right)
    if width == 16
      source = left.__spec_add16_equal_raw(right)
    c_oracle = ccall("w_bigint_add", left, right)
    if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
      << "FAIL direct source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    i += 1
  if i != count
    << "FAIL differential count"
    exit 1

run_width(4, 40_000)
run_width(8, 40_000)
run_width(16, 20_000)

<< "PASS BigInt add@4/8/16 direct source/C differential"
