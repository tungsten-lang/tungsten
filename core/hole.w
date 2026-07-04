# Hole — countable but indivisible. "Half a hole is still one hole."
#
# Source syntax: `1 hole`, `3 holes`. A hole is a discrete quantum: any
# arithmetic that would produce a fractional positive count rounds UP to
# the next whole hole. Zero kills it; negative counts raise.
#
#   1 hole + 1 hole       = 2 holes
#   0.5 hole + 0.5 hole   = 1 hole
#   0.5 hole + 0.7 hole   = 2 holes      (ceil(1.2))
#   0.5 * 1 hole          = 1 hole       (any nonzero scalar saturates up)
#   1 hole / 2            = 1 hole       (ceil)
#   2 holes / 2           = 1 hole       (normal)
#   0 * 1 hole            = 0 holes      (zero is allowed)
#   1 hole - 2 holes      → error        (negative count undefined)
#
# Implemented as a Quantity with a custom dimension named "hole"; the
# ceiling-quantization rule lives in Quantity arithmetic, dispatched by
# the `hole?` predicate. The post-arithmetic snap function is
# `Quantity.snap_hole(q)` which calls `Quantity.hole_count(value)`.
+ Hole
  is Comparable

  -> hole?
    true

  # The operator methods (+, -, *, /) are implemented at the runtime
  # level — parser handles `/` and `*` specially for arity-method names.
  # Semantics: any positive arithmetic result rounds up via snap_count;
  # zero stays zero; negative raises.

  # Snap a numeric count to the hole-quantization rule:
  #   x == 0       → 0
  #   x > 0        → ceil(x)
  #   x < 0        → raise
  -> snap_count(x)
    if x == 0
      0
    elsif x > 0
      x.ceil
    else
      raise("negative count of holes is undefined")

  -> ==(other)
    other.is_a?(Hole) && self.count == other.count

  -> <=>(other)
    other.is_a?(Hole) ? self.count <=> other.count : nil

  -> hash
    [self.count, "hole"].hash

  -> to_s
  -> inspect
    self.to_s
