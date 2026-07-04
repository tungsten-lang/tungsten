# Heap — sorites top element. "If you take one grain from a heap, you
# still have a heap."
#
# Source syntax: `1 heap`, `2 heaps`. Closer to infinity than to any finite
# quantity. Arithmetic is fully absorbing — adding, removing, multiplying
# by anything finite yields a heap. The only kill is multiplication by
# zero (the annihilator).
#
#   1 heap - 3 heaps   = 1 heap
#   1 heap + 3         = 1 heap
#   1 heap * k         = 1 heap   (for any nonzero k)
#   1 heap * 0         = 0 heap
#   1 heap > N         = true     (for any finite N)
#   1 heap == 1 heap   = true
#
# Implemented as a Quantity with a custom dimension named "heap"; the
# absorbing semantics live in Quantity arithmetic, dispatched by the
# `heap?` predicate.
+ Heap
  is Comparable

  -> heap?
    true

  # All heap arithmetic returns self (or zero when annihilated). The
  # operator methods (+, -, *, /) are implemented at the runtime level
  # since the parser handles `/` and `*` specially. Semantics:
  #
  #   self + anything             → self
  #   self - anything             → self
  #   self * 0                    → 0 (annihilator)
  #   self * nonzero              → self
  #   self / 0                    → raises
  #   self / nonzero              → self

  # heap > anything finite is true; heap == heap is true; heap == finite is false.
  -> <=>(other)
    other.is_a?(Heap) ? 0 : 1

  -> ==(other)
    other.is_a?(Heap)

  -> hash
    "heap".hash

  -> to_s
    "1 heap"

  -> inspect
    self.to_s
