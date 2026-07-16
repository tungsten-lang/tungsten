# SmallArray
#
# Frozen, stack-allocatable, packed array. Up to 255 elements.
# Element type chosen at construction (u4..f64, w64).
#
# No start/cap (size = cap, no shift). No owned/pooled/view flags
# (never malloc'd, never aliased into a borrow contract). First byte
# stores the full ebits code, including extended signed/float sentinels.
#
# Use cases: tensor shapes, strides, top-k indices, kernel scalar args,
# memoization keys.

+ SmallArray
  is Enumerable

  - data (WSmallArray)
      u8   ebits
      u8   size
      u8[] slots

  -> __enumerable_iteration_mode
    1

  # Header size is a u8, so it always fits the immediate-Integer payload.
  # Construct the canonical WValue tag in source and avoid an out-of-line
  # w_int call on every public query.
  -> size
    n = $size ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  # SmallArray is frozen: capacity is exactly its header size.
  -> cap
    n = $size ## i64
    tag = -1_688_849_860_263_936 ## i64  # 0xFFFA000000000000
    wvalue_from_bits((tag | n) ## i64)

  -> empty?
    n = $size ## i64
    if n == 0
      return true
    false

  -> each/&
    $size -> &(self[i]) : self

  -> sort(&)
    if block_given?
      to_a.sort -> (a, b)
        &(a, b)
    else
      to_a.sort

  -> shuffle(*opts)
    to_a.shuffle(*opts)

  -> rotate(count = 1)
    to_a.rotate(count)
