# Compiled-only direct native/C differential for the exact mul1@24 leaf.
# Build with BN_BIGINT_MUL1_24_SRC_DIRECT=0: public multiplication then stays
# on C, while this spec calls the raw native worker explicitly.

fn __spec_mul1_24_next(state) (u64) u64
  state * 6364136223846793005 + 1442695040888963407

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_mul1_24_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_mul1_24_raw($value ## i64, other$value ## i64)
    )

  -> __spec_set_limb(i, value)(i64 u64)
    $limbs[i] = value
    self

state = 0x9e3779b97f4a7c15 ## u64
high_bit = 9223372036854775808 ## u64
wide = 1 << 1472
word = 1 << 63
i = 0
while i < 100_000
  iteration = i ## u64
  j = 0
  while j < 24
    state = __spec_mul1_24_next(state) ## u64
    limb = state ## u64
    if j == 23
      limb = ((limb ^ (limb >> 23)) + iteration + 1) ## u64
      if limb == 0
        limb = 1 ## u64
    wide.__spec_set_limb(j, limb)
    j += 1
  state = __spec_mul1_24_next(state) ## u64
  word.__spec_set_limb(0, state | high_bit | 1 ## u64)

  if (i & 1) == 0
    source = wide.__spec_mul1_24_raw(word)
    c_oracle = ccall("w_bigint_mul_builtin_exact", wide, word)
  else
    source = word.__spec_mul1_24_raw(wide)
    c_oracle = ccall("w_bigint_mul_builtin_exact", word, wide)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt mul1@24 direct source/C differential (100000)"
