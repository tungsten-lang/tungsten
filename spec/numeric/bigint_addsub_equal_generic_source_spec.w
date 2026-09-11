# Positive equal-width BigInt addition and subtraction at every width from
# 5 through 23. Widths 8 and 16 take their exact fixed-kernel leaves; every
# other width takes the generic quad-loop leaf that replaces C's blocked
# bn_add_n / bn_sub_n route through bigint_{add,sub}_equal_fast: the same
# hot capacity class, C's unconditional carry publication (add) and its
# top-limb publication or trim-and-demote finisher (sub).

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
  tag = "w" + width.to_s()
  check_add(tag + ".add.minimum", base, base + 1, width)
  check_add(tag + ".add.ordinary", base * 17 + 37, base * 19 + 91, width)
  check_add(tag + ".add.high_bit", (top >> 1) + 29, (top >> 1) + 43, width + 1)
  check_add(tag + ".add.maximum", top - 1, top - 3, width + 1)
  check_add(tag + ".add.ripple", top - 1, 1 + base, width + 1)
  check_sub(tag + ".sub.ordinary", base * 19 + 91, base * 17 + 37)
  check_sub(tag + ".sub.reverse", base * 17 + 37, base * 19 + 91)
  check_sub(tag + ".sub.ripple_full", top - 1, (top - 1) - 1)
  check_sub(tag + ".sub.top_tie", base * 5 + 1000, base * 5 + 7)
  check_sub(tag + ".sub.top_tie_reverse", base * 5 + 7, base * 5 + 1000)
  check_sub(tag + ".sub.shrink", base * 5 + (1 << 70), base * 5 + 3)
  check_sub(tag + ".sub.to_inline", base * 5 + 40, base * 5 + 3)
  check_sub(tag + ".sub.to_inline_negative", base * 5 + 3, base * 5 + 40)
  equal_left = base * 5 + 37
  equal_right = (base * 5 + 38) - 1
  check_sub(tag + ".sub.distinct_equal", equal_left, equal_right)
  check(tag + ".sub.identity", equal_left - equal_left, 0)
  positive = (top >> 1) + 71
  other = base * 31 + 17
  negative = 0 - positive
  check(tag + ".control.add.mixed_sign", negative + other,
        ccall("w_bigint_add", negative, other))
  check(tag + ".control.sub.both_negative", negative - (0 - other),
        ccall("w_bigint_sub", negative, 0 - other))
  state = 0x9e3779b97f4a7c15 + width
  i = 0
  while i < 400
    pair = pair_at(width, i, state)
    left = pair[0]
    right = pair[1]
    state = pair[2]
    got = left + right
    oracle = ccall("w_bigint_add", left, right)
    if got != oracle || got.__spec_header_size() != oracle.__spec_header_size()
      << "FAIL " + tag + " add differential at " + i.to_s()
      exit 1
    got = left - right
    oracle = ccall("w_bigint_sub", left, right)
    if got != oracle || header_of(got) != header_of(oracle)
      << "FAIL " + tag + " sub differential at " + i.to_s()
      exit 1
    i += 1
  check(tag + ".differential.count", i, 400)

width = 5
while width <= 23
  run_width(width)
  width += 1

# Widths past the family stay on C's tree.
twentyfive_a = (1 << 1536) + 37
twentyfive_b = (1 << 1537) + 41
check("control.add.twentyfive", twentyfive_a + twentyfive_b,
      ccall("w_bigint_add", twentyfive_a, twentyfive_b))
check("control.sub.twentyfive", twentyfive_a - twentyfive_b,
      ccall("w_bigint_sub", twentyfive_a, twentyfive_b))

<< "bigint_addsub_equal_generic_source_spec: all checks passed"
