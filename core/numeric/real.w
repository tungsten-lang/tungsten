# Real — the totally ordered numbers: Int, Float, Decimal and their
# fixed-width variants. What separates Real from Hypercomplex is a
# genuine total order, so value comparison and sign live here.
+ Real < Number

  # Three-way comparison by value. Concrete types supply primitive
  # < and >; Comparable derives <, <=, >, >=, == from this.
  -> <=>/1
    self > @1 ? 1 : (self < @1 ? -1 : 0)

  -> negative?
    self < 0

  -> positive?
    self > 0

  -> abs
    negative? ? -self : self

  -> sign
    self < 0 ? -1 : (self == 0 ? 0 : 1)

  -> divmod/1
    [ self / @1, self % @1 ]

  # Restrict self to [@1, @2]: returns @1 if self < @1, @2 if self > @2,
  # else self. Caller is responsible for @1 <= @2.
  -> clamp/2
    self < @1 ? @1 : (self > @2 ? @2 : self)

  # Inclusive range check: @1 <= self <= @2.
  -> between?/2
    self >= @1 && self <= @2
