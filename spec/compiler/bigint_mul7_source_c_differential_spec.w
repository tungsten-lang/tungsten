# Compiled-only direct native/C differential for the exact mul@7 outer leaf.

+ BigInt
  -> __spec_header_size
    $size

  -> __spec_mul7_raw(other)(BigInt)
    wvalue_from_bits(
      __bigint_mul7_raw($value ## i64, other$value ## i64)
    )

mask64 = (1 << 64) - 1
state = 0x9e3779b97f4a7c15
i = 0
while i < 100_000
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  a0 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  a1 = state
  state = (state * 3202034522624059733 + 1) & mask64
  a2 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  a3 = state
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  a4 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  a5 = state
  atop = ((state ^ (state >> 23)) + i + 1) & mask64
  if atop == 0
    atop = 1
  state = (state * 3202034522624059733 + 1) & mask64
  b0 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  b1 = state
  state = (state * 6364136223846793005 + 1442695040888963407) & mask64
  b2 = state
  state = (state * 2862933555777941757 + 3037000493) & mask64
  b3 = state
  state = (state * 3202034522624059733 + 1) & mask64
  b4 = state
  state = (state * 3935559000370003845 + 2691343689449507681) & mask64
  b5 = state
  btop = ((state ^ (state >> 29)) + i + 3) & mask64
  if btop == 0
    btop = 1
  left = (atop << 384) + (a5 << 320) + (a4 << 256) + (a3 << 192) + (a2 << 128) + (a1 << 64) + a0
  right = (btop << 384) + (b5 << 320) + (b4 << 256) + (b3 << 192) + (b2 << 128) + (b1 << 64) + b0
  source = left.__spec_mul7_raw(right)
  c_oracle = ccall("w_bigint_mul_builtin_exact", left, right)
  if source != c_oracle || source.__spec_header_size() != c_oracle.__spec_header_size()
    << "FAIL direct source/C differential at " + i.to_s()
    exit 1
  i += 1

if i != 100_000
  << "FAIL differential count"
  exit 1

<< "PASS BigInt mul@7 direct source/C differential (100000)"
