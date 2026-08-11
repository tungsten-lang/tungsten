# `tungsten check` must reach lowering/type inference, not stop after parsing.
+ FourRequired
  -> new(@a, @b, @c, @d)
    self

FourRequired.new(1, 2, 3)
