# Compiled-only direct native/C differential for the exact sqr@16 split leaf.
# Build with BN_BIGINT_SQR16_SRC_DIRECT=0: the public exact boundary then stays
# on C, while this spec calls the raw native worker explicitly.

fn __spec_sqr16_next(state) (u64) u64
  state * 6364136223846793005 + 1442695040888963407

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_sqr16_raw
    wvalue_from_bits(__bigint_sqr16_raw($value ## i64, $value ## i64))

  -> __spec_set_limb(i, value)(i64 u64)
    $limbs[i] = value
    self

state = 0x9e3779b97f4a7c15 ## u64
value = 1 << 960
i = 0
while i < 100_000
  iteration = i ## u64
  j = 0
  while j < 16
    state = __spec_sqr16_next(state) ## u64
    limb = state ## u64
    if j == 15
      limb = ((limb ^ (limb >> 23)) + iteration + 1) ## u64
      if limb == 0
        limb = 1 ## u64
    value.__spec_set_limb(j, limb)
    j += 1

  # Square ignores the sign, but retain alternating effective signs without
  # allocating or changing the positive raw header used by the admitted arm.
  operand = value
  if (i & 1) == 1
    operand = wvalue_from_bits(wvalue_bits(value) ^ 140737488355328)
  source = operand.__spec_sqr16_raw()
  c_oracle = ccall("w_bigint_mul_builtin_exact", operand, operand)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt sqr@16 direct source/C differential (100000)"
