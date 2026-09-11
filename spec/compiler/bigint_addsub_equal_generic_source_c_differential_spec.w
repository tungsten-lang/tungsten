# Compiled-only direct native/C differential for the generic equal-width
# add/sub leaves at every width from 5 through 23 (the fixed widths 8 and
# 16 are exercised through the same generic wrapper here as a cross-check).

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_add_generic_raw(other, width)(BigInt Int)
    wvalue_from_bits(
      __bigint_add_equal_generic_raw(
        $value ## i64, other$value ## i64, width ## i64
      )
    )

  -> __spec_sub_generic_raw(other, width)(BigInt Int)
    wvalue_from_bits(
      __bigint_sub_equal_generic_raw(
        $value ## i64, other$value ## i64, width ## i64
      )
    )

-> header_of(value)
  return 0 if value.is_a?(Int) && !value.is_a?(BigInt)
  value.__spec_header_size()

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
  state = 0x5851f42d4c957f2d + width
  i = 0
  while i < count
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    if i % 4 == 3
      right = (right >> (64 * (width - 1))) << (64 * (width - 1))
      right = right + (left & ((1 << (64 * (width - 1))) - 1))
      if i % 8 == 7
        right = left + 0
      else
        right = right + (i % 3) - 1
    source = left.__spec_add_generic_raw(right, width)
    c_oracle = ccall("w_bigint_add", left, right)
    if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
      << "FAIL direct add source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    source = left.__spec_sub_generic_raw(right, width)
    c_oracle = ccall("w_bigint_sub", left, right)
    if source != c_oracle || header_of(source) != header_of(c_oracle)
      << "FAIL direct sub source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    reverse = right.__spec_sub_generic_raw(left, width)
    c_reverse = ccall("w_bigint_sub", right, left)
    if reverse != c_reverse || header_of(reverse) != header_of(c_reverse)
      << "FAIL direct reverse sub source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    i += 1

width = 5
while width <= 23
  run_width(width, 4_000)
  width += 1

<< "PASS BigInt generic equal-width add/sub direct source/C differential"
