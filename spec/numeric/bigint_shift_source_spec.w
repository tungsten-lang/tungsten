# Focused source-seam coverage for BigInt << and >>. The division oracle is
# independent of the shift kernels and accounts for arithmetic right-shift
# rounding toward negative infinity.

use ../../core/numeric/big_int

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

# Include both carry-producing and no-carry shapes around the native left-shift
# funnel's 64/65 and 224/225-limb admission seams.
widths = [64, 65, 127, 128, 129, 255, 256, 257, 4095, 4096, 4097, 4159, 14271, 14272, 14335, 14336, 14399]
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

# The native one-limb right-shift arm is admitted only when the result fits
# signed i48. Pin an ordinary demotion and the exact top boundary; the k=16
# neighbor remains heap-valued and exercises the C control route.
one_native = (1 << 50) + 12345
check("one_native.infix", one_native >> 13 == one_native / (1 << 13))
check("one_native.explicit", one_native.>>(13) == one_native / (1 << 13))
one_max = (1 << 64) - 1
check("one_native.i48_max", one_max >> 17 == 140737488355327)
check("one_native.heap_control", one_max >> 16 == one_max / (1 << 16))
check("one_native.negative_i48_min", (0 - one_max) >> 17 == -140737488355328)
check("one_native.negative_heap_control", (0 - one_max) >> 16 == -281474976710656)
check("one_native.negative_rounding", (0 - one_native) >> 13 == (0 - ((one_native + (1 << 13) - 1) / (1 << 13))))
check("one_native.overshift_positive", one_max >> 100 == 0)
check("one_native.overshift_negative", (0 - one_max) >> 100 == -1)
check("one_native.negative_left_overshift_positive", one_max << -100 == 0)
check("one_native.negative_left_overshift_negative", (0 - one_max) << -100 == -1)

multi_tail_unaligned = (1 << 250) + (1 << 130) + 3
multi_tail_aligned = (1 << 192) + (1 << 100) + 3
check("multi_tail.unaligned", multi_tail_unaligned >> 205 == (1 << 45))
check("multi_tail.unaligned_explicit", multi_tail_unaligned.>>(205) == (1 << 45))
check("multi_tail.aligned", multi_tail_aligned >> 192 == 1)
check("multi_tail.i48_max", ((140737488355327 << 192) + 7) >> 192 == 140737488355327)
check("multi_tail.heap_control", ((140737488355328 << 192) + 7) >> 192 == 140737488355328)
check("multi_tail.negative_unaligned", (0 - multi_tail_unaligned) >> 205 == (0 - (1 << 45) - 1))
check("multi_tail.negative_unaligned_explicit", (0 - multi_tail_unaligned).>>(205) == (0 - (1 << 45) - 1))
check("multi_tail.negative_high_sticky", (0 - ((1 << 250) + (1 << 127))) >> 205 == (0 - (1 << 45) - 1))
check("multi_tail.negative_aligned_sticky", (0 - multi_tail_aligned) >> 192 == -2)
check("multi_tail.negative_i48_min", (0 - (140737488355328 << 192)) >> 192 == -140737488355328)
check("multi_tail.negative_heap_control", (0 - ((140737488355328 << 192) + 7)) >> 192 == -140737488355329)

wide_tail_unaligned = (1 << 4090) + (1 << 2000) + 3
wide_tail_aligned = (1 << 4032) + (1 << 2000) + 3
check("wide_tail.negative_unaligned", (0 - wide_tail_unaligned) >> 4045 == (0 - (1 << 45) - 1))
check("wide_tail.negative_unaligned_explicit", (0 - wide_tail_unaligned).>>(4045) == (0 - (1 << 45) - 1))
check("wide_tail.negative_aligned", (0 - wide_tail_aligned) >> 4032 == -2)
check("wide_tail.negative_sparse_fallback", (0 - ((1 << 4090) + (1 << 2000))) >> 4045 == (0 - (1 << 45) - 1))

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

# Overshift completion is O(1) and deliberately admitted beyond the ordinary
# 4096-limb source-shim band. Pin both infix seam routing and explicit sends at
# the exact 4097-limb width boundary.
band_over_shift = 4097 * 64
check("band.4097.overshift_positive", band_over >> band_over_shift == 0)
check("band.4097.overshift_negative", (0 - band_over) >> band_over_shift == -1)
check("band.4097.overshift_positive_explicit", band_over.>>(band_over_shift) == 0)
check("band.4097.overshift_negative_explicit", (0 - band_over).>>(band_over_shift) == -1)
check("band.4097.negative_left_overshift_positive", band_over << (0 - band_over_shift) == 0)
check("band.4097.negative_left_overshift_negative", (0 - band_over) << (0 - band_over_shift) == -1)
check("band.4097.negative_left_overshift_positive_explicit", band_over.<<(0 - band_over_shift) == 0)
check("band.4097.negative_left_overshift_negative_explicit", (0 - band_over).<<(0 - band_over_shift) == -1)

<< "bigint_shift_source_spec: all 1010 checks passed"
