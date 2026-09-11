# Compiled-only direct native/C differential for the exact add@2, add@24, and
# sub@2/3/4/8/16/24 leaves. The public C boundaries stay available as
# independent oracles.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_add2_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_add2_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_add24_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_add24_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub2_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub2_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub3_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub3_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub4_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub4_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub8_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub8_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub16_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub16_equal_raw($value ## i64, other$value ## i64)
    )

  -> __spec_sub24_equal_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_sub24_equal_raw($value ## i64, other$value ## i64)
    )

-> header_of(value)
  return 0 if value.is_a?(Int) && !value.is_a?(BigInt)
  value.__spec_header_size()

# Deterministic N-limb operand pairs; every top limb is nonzero so the
# operands are exactly N limbs wide.
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

-> run_add(width, count)
  state = 0x9e3779b97f4a7c15 + width
  i = 0
  while i < count
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    source = nil
    if width == 2
      source = left.__spec_add2_equal_raw(right)
    if width == 24
      source = left.__spec_add24_equal_raw(right)
    c_oracle = ccall("w_bigint_add", left, right)
    if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
      << "FAIL direct add source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    i += 1

-> sub_source(width, left, right)
  return left.__spec_sub2_equal_raw(right) if width == 2
  return left.__spec_sub3_equal_raw(right) if width == 3
  return left.__spec_sub4_equal_raw(right) if width == 4
  return left.__spec_sub8_equal_raw(right) if width == 8
  return left.__spec_sub16_equal_raw(right) if width == 16
  left.__spec_sub24_equal_raw(right)

-> run_sub(width, count)
  state = 0x5851f42d4c957f2d + width
  i = 0
  while i < count
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    # Every fourth case shares the top limb so the full scan and the
    # cancelling finisher are exercised; every eighth cancels entirely.
    if i % 4 == 3
      right = (right >> (64 * (width - 1))) << (64 * (width - 1))
      right = right + (left & ((1 << (64 * (width - 1))) - 1))
      if i % 8 == 7
        right = left + 0
      else
        right = right + (i % 3) - 1
    source = sub_source(width, left, right)
    c_oracle = ccall("w_bigint_sub", left, right)
    if source != c_oracle || header_of(source) != header_of(c_oracle)
      << "FAIL direct sub source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    reverse = sub_source(width, right, left)
    c_reverse = ccall("w_bigint_sub", right, left)
    if reverse != c_reverse || header_of(reverse) != header_of(c_reverse)
      << "FAIL direct reverse sub source/C differential at width " + width.to_s() + " case " + i.to_s()
      exit 1
    i += 1

run_add(2, 40_000)
run_add(24, 10_000)
run_sub(2, 30_000)
run_sub(3, 30_000)
run_sub(4, 30_000)
run_sub(8, 20_000)
run_sub(16, 10_000)
run_sub(24, 10_000)

<< "PASS BigInt add@2/24 and sub@2/3/4/8/16/24 direct source/C differential"
