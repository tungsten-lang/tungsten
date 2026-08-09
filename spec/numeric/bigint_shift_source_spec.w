# Focused source-seam coverage for BigInt << and >>. The division oracle is
# independent of the shift kernels and accounts for arithmetic right-shift
# rounding toward negative infinity.

-> check(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

-> check_shift(name, x, k)
  scale = 1 << k
  left = x << k
  check(name + ".left_inverse", (left >> k) == x)

  expected = 0
  if x >= 0
    expected = x / scale
  else
    expected = 0 - (((0 - x) + scale - 1) / scale)
  check(name + ".right_floor", (x >> k) == expected)
  check(name + ".negative_left_count", (x << (0 - k)) == (x >> k))
  check(name + ".negative_right_count", (x >> (0 - k)) == left)

widths = [64, 65, 127, 128, 129, 255, 256, 257, 4095, 4096, 4097]
shifts = [1, 13, 63, 64, 65, 200, 1000]

i = 0
while i < widths.size
  bits = widths[i]
  x = (1 << bits) + (1 << (bits / 2)) + 12345
  j = 0
  while j < shifts.size
    k = shifts[j]
    check_shift("positive.[bits].[k]", x, k)
    check_shift("negative.[bits].[k]", 0 - x, k)
    j += 1
  i += 1

one = (1 << 60) + 17
check("one_limb.left", (one << 13) >> 13 == one)
check("one_limb.right", one >> 13 == one / (1 << 13))

heap = (1 << 200) + 33
check("zero.left.identity", wvalue_bits(heap << 0) == wvalue_bits(heap))
check("zero.right.identity", wvalue_bits(heap >> 0) == wvalue_bits(heap))
check("huge.right.positive", heap >> 10000 == 0)
check("huge.right.negative", (0 - heap) >> 10000 == -1)
check("explicit.left", heap.<<(13) == heap << 13)
check("explicit.right", heap.>>(13) == heap >> 13)

# Source-seam admission boundary: 4096 limbs is admitted, 4097 falls back to
# C. Both must remain exact and, critically, neither route may recurse.
band_hi = (1 << (64 * 4095 + 10)) + 12345
band_over = (1 << (64 * 4096 + 10)) + 12345
check_shift("band.4096.positive", band_hi, 13)
check_shift("band.4096.negative", 0 - band_hi, 13)
check_shift("band.4097.positive", band_over, 13)
check_shift("band.4097.negative", 0 - band_over, 13)

<< "bigint_shift_source_spec: all 640 checks passed"
