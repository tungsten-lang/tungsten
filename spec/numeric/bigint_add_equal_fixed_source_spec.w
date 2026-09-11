# Distinct positive equal-width BigInt addition at the fixed-kernel widths
# 4, 8, and 16. On macOS ARM64 each is the exact native Tungsten port of
# bigint_add_equal_fast's fixed arm (bn_add{4,8,16}_fixed): hot power-of-two
# allocation, the literal load/add-with-carry/store schedule, an
# unconditional carry-limb store, and a normalized size of N or N+1.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> check_add(name, left, right, expected_size)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left + right
  oracle = ccall("w_bigint_add", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header_size", got.__spec_header_size(), expected_size)
  check(name + ".commuted", right + left, got)
  check(name + ".left_unchanged", left.to_s(), left_before)
  check(name + ".right_unchanged", right.to_s(), right_before)

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

-> run_width(width)
  base = 1 << (64 * (width - 1))
  top = 1 << (64 * width)
  tag = "add" + width.to_s()

  # No carry from the top limb: the result stays normalized at N limbs.
  check_add(tag + ".minimum", base, base + 1, width)
  check_add(tag + ".ordinary", base * 17 + 37, base * 19 + 91, width)

  # Carry from the top limb publishes limb N and grows the header.
  check_add(tag + ".high_bit", (top >> 1) + 29, (top >> 1) + 43, width + 1)
  check_add(tag + ".maximum", top - 1, top - 3, width + 1)

  # A full carry chain through every limb.
  check_add(tag + ".ripple", top - 1, 1 + base, width + 1)

  # Equal numeric values in distinct boxes still take the binary-add leaf.
  equal_left = base + 37
  equal_right = (base + 38) - 1
  check_add(tag + ".distinct_equal", equal_left, equal_right, width)

  # Signed shapes keep the existing C routes.
  positive = (top >> 1) + 71
  other = base * 31 + 17
  negative = 0 - positive
  check(tag + ".control.mixed_sign", negative + other,
        ccall("w_bigint_add", negative, other))
  check(tag + ".control.both_negative", negative + (0 - other),
        ccall("w_bigint_add", negative, 0 - other))

  # Deterministic public-operator differential across both result widths.
  state = 0x9e3779b97f4a7c15 + width
  i = 0
  while i < 4_000
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    got = left + right
    oracle = ccall("w_bigint_add", left, right)
    if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
      << "FAIL " + tag + " differential at " + i.to_s()
      exit 1
    i += 1
  check(tag + ".differential.count", i, 4_000)

run_width(4)
run_width(8)
run_width(16)

# Neighboring equal widths that remain on C's tuned tree.
five_a = (1 << 256) + 37
five_b = (1 << 257) + 41
check("control.five", five_a + five_b, ccall("w_bigint_add", five_a, five_b))
twelve_a = (1 << 704) + 37
twelve_b = (1 << 705) + 41
check("control.twelve", twelve_a + twelve_b, ccall("w_bigint_add", twelve_a, twelve_b))
twentyfour_a = (1 << 1472) + 37
twentyfour_b = (1 << 1473) + 41
check("control.twentyfour", twentyfour_a + twentyfour_b,
      ccall("w_bigint_add", twentyfour_a, twentyfour_b))

<< "bigint_add_equal_fixed_source_spec: all checks passed"
