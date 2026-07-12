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
