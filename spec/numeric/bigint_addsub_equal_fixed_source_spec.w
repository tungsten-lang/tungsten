# Distinct positive equal-width BigInt subtraction at widths 2, 3, 4, 8, 16,
# and 24, plus positive addition at widths 2 and 24. On macOS ARM64 each is
# the exact native Tungsten port of C's boxed equal-width route
# (bigint_add_two_limb_magnitudes at width two; bigint_add_equal_fast /
# bigint_sub_equal_fast with the fixed bn_{add,sub}N_fixed kernels above it):
# the same hot allocation class, the literal kernel schedule, C's top-limb
# publication, and its trim-and-demote finisher for cancelling differences.

+ BigInt
  -> __spec_header_size
    $size

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> header_of(value)
  return 0 if value.is_a?(Int) && !value.is_a?(BigInt)
  value.__spec_header_size()

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

-> check_sub(name, left, right)
  left_before = left.to_s()
  right_before = right.to_s()
  got = left - right
  oracle = ccall("w_bigint_sub", left, right)
  check(name + ".oracle", got, oracle)
  check(name + ".header", header_of(got), header_of(oracle))
  check(name + ".negated", right - left, 0 - got)
  check(name + ".round_trip", got + right, left)
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

-> run_add_width(width)
  base = 1 << (64 * (width - 1))
  top = 1 << (64 * width)
  tag = "add" + width.to_s()
  check_add(tag + ".minimum", base, base + 1, width)
  check_add(tag + ".ordinary", base * 17 + 37, base * 19 + 91, width)
  check_add(tag + ".high_bit", (top >> 1) + 29, (top >> 1) + 43, width + 1)
  check_add(tag + ".maximum", top - 1, top - 3, width + 1)
  check_add(tag + ".ripple", top - 1, 1 + base, width + 1)
  positive = (top >> 1) + 71
  other = base * 31 + 17
  negative = 0 - positive
  check(tag + ".control.mixed_sign", negative + other,
        ccall("w_bigint_add", negative, other))
  check(tag + ".control.both_negative", negative + (0 - other),
        ccall("w_bigint_add", negative, 0 - other))
  state = 0x9e3779b97f4a7c15 + width
  i = 0
  while i < 3_000
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
  check(tag + ".differential.count", i, 3_000)

-> run_sub_width(width)
  base = 1 << (64 * (width - 1))
  top = 1 << (64 * width)
  tag = "sub" + width.to_s()
  # Larger minus smaller and the reverse, top limbs differing.
  check_sub(tag + ".ordinary", base * 19 + 91, base * 17 + 37)
  check_sub(tag + ".reverse", base * 17 + 37, base * 19 + 91)
  # Borrow rippling through every limb.
  check_sub(tag + ".ripple", base * 2, base * 2 - 1 - base + 1)
  check_sub(tag + ".ripple_full", top - 1, (top - 1) - 1)
  # Equal top limbs: the full magnitude scan decides.
  check_sub(tag + ".top_tie", base * 5 + 1000, base * 5 + 7)
  check_sub(tag + ".top_tie_reverse", base * 5 + 7, base * 5 + 1000)
  # Cancellation down to fewer limbs, one limb, an i48 inline result, and
  # exact zero in distinct boxes.
  check_sub(tag + ".shrink", base * 5 + (1 << 70), base * 5 + 3)
  check_sub(tag + ".to_one_limb", base * 5 + (1 << 60), base * 5 + 3)
  check_sub(tag + ".to_inline", base * 5 + 40, base * 5 + 3)
  check_sub(tag + ".to_inline_negative", base * 5 + 3, base * 5 + 40)
  equal_left = base * 5 + 37
  equal_right = (base * 5 + 38) - 1
  check_sub(tag + ".distinct_equal", equal_left, equal_right)
  check(tag + ".identity", equal_left - equal_left, 0)
  # Signed shapes keep the existing C routes.
  positive = (top >> 1) + 71
  other = base * 31 + 17
  negative = 0 - positive
  check(tag + ".control.mixed_sign", negative - other,
        ccall("w_bigint_sub", negative, other))
  check(tag + ".control.both_negative", negative - (0 - other),
        ccall("w_bigint_sub", negative, 0 - other))
  state = 0x5851f42d4c957f2d + width
  i = 0
  while i < 3_000
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    got = left - right
    oracle = ccall("w_bigint_sub", left, right)
    if got != oracle || header_of(got) != header_of(oracle)
      << "FAIL " + tag + " differential at " + i.to_s()
      exit 1
    i += 1
  check(tag + ".differential.count", i, 3_000)

run_add_width(2)
run_add_width(24)
run_sub_width(2)
run_sub_width(3)
run_sub_width(4)
run_sub_width(8)
run_sub_width(16)
run_sub_width(24)

# Neighboring equal widths that remain on C's tuned tree.
five_a = (1 << 256) + 37
five_b = (1 << 257) + 41
check("control.add.five", five_a + five_b, ccall("w_bigint_add", five_a, five_b))
check("control.sub.five", five_a - five_b, ccall("w_bigint_sub", five_a, five_b))
thirtytwo_a = (1 << 1984) + 37
thirtytwo_b = (1 << 1985) + 41
check("control.add.thirtytwo", thirtytwo_a + thirtytwo_b,
      ccall("w_bigint_add", thirtytwo_a, thirtytwo_b))
check("control.sub.thirtytwo", thirtytwo_a - thirtytwo_b,
      ccall("w_bigint_sub", thirtytwo_a, thirtytwo_b))

<< "bigint_addsub_equal_fixed_source_spec: all checks passed"
