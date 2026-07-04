# Number — root of the numeric tower. Every concrete number is either a
# Real (totally ordered) or a Hypercomplex (ordered only by magnitude).
+ Number
  is Comparable

  # Three-way comparison. Required by Comparable, and supplied by
  # Real (compares by value) and Hypercomplex (compares by magnitude).
  -> <=>/1

  # Magnitude of the value.
  -> abs

  # Squared magnitude — exact, and cheaper when the root isn't needed.
  -> abs2
    abs ** 2

  -> zero?
    self == 0

  -> nonzero?
    !zero?

  -> one?
    self == 1

  # Additive identity. Hypercomplex overrides with its structural [0,…,0].
  -> zero
    0

  # Multiplicative identity. Hypercomplex overrides with [1,0,…,0].
  -> one
    1

  # Square: self * self. Used by Array#pythagorean (`/sq:sum.sqrt`).
  -> sq
    self * self

  # Cube: self³.
  -> cube
    self * sq

  # Pairwise min/max via Comparable's `<` and `>`. For Real this is by
  # value; for Hypercomplex this is by magnitude (same `<=>` it uses).
  -> min/1
    self < @1 ? self : @1

  -> max/1
    self > @1 ? self : @1

  # Unary negation: -self. Every Number negates.
  -> negate

  -> -@
    negate

  # Human-readable string form.
  -> to_s
