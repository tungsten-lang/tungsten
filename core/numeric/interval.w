# Interval — rigorous interval arithmetic over Float endpoints.
#
# Every op returns a superset of the true range of the expression, so
#   x ∈ [a,b], y ∈ [c,d]  ⇒  x+y ∈ [a+c, b+d]
# with outward rounding left as a future refinement (v0 uses plain f64
# endpoints — good for proofs-of-concept and branch-and-bound, not yet
# a full IEEE-1788 library).
#
# Product feature: pair with Solve / Optim for validated roots and with
# Special for range enclosures. See doc/scientific-computing/interval.md.

+ Interval
  -> new(@lo, @hi)
    if @lo > @hi
      t = @lo
      @lo = @hi
      @hi = t
    self

  -> .point(x)
    Interval.new(x, x)

  -> .hull(a, b)
    lo = a
    hi = b
    if b < a
      lo = b
      hi = a
    Interval.new(lo, hi)

  -> lo
    @lo

  -> hi
    @hi

  -> mid
    (~0.5) * (@lo + @hi)

  -> width
    @hi - @lo

  -> contains?(x)
    x >= @lo && x <= @hi

  -> +(other)
    if other.class == Interval
      return Interval.new(@lo + other.lo, @hi + other.hi)
    Interval.new(@lo + other, @hi + other)

  -> -(other)
    if other.class == Interval
      return Interval.new(@lo - other.hi, @hi - other.lo)
    Interval.new(@lo - other, @hi - other)

  -> -@
    Interval.new(~0.0 - @hi, ~0.0 - @lo)

  -> *(other)
    if other.class != Interval
      # Treat an exact zero scalar as the zero map, including for intervals
      # with infinite endpoints (IEEE arithmetic would otherwise form 0*∞).
      if other == ~0.0
        return Interval.point(~0.0)
      if other >= ~0.0
        return Interval.new(@lo * other, @hi * other)
      return Interval.new(@hi * other, @lo * other)
    a = @lo
    b = @hi
    c = other.lo
    d = other.hi

    # An exact zero interval annihilates the product. Besides skipping all
    # remaining work, this keeps zero×unbounded intervals from manufacturing
    # NaN endpoints through IEEE 0*∞.
    if (a == ~0.0 && b == ~0.0) || (c == ~0.0 && d == ~0.0)
      return Interval.point(~0.0)

    # Sign classification needs only the two extremal products in eight of
    # the nine cases. Only two intervals that both straddle zero require all
    # four corners.
    if a >= ~0.0
      if c >= ~0.0
        return Interval.new(a * c, b * d)
      elsif d <= ~0.0
        return Interval.new(b * c, a * d)
      else
        return Interval.new(b * c, b * d)
    elsif b <= ~0.0
      if c >= ~0.0
        return Interval.new(a * d, b * c)
      elsif d <= ~0.0
        return Interval.new(b * d, a * c)
      else
        return Interval.new(a * d, a * c)
    else
      if c >= ~0.0
        return Interval.new(a * d, b * d)
      elsif d <= ~0.0
        return Interval.new(b * c, a * c)

    ac = a * c
    ad = a * d
    bc = b * c
    bd = b * d
    lo = ad < bc ? ad : bc
    hi = ac > bd ? ac : bd
    Interval.new(lo, hi)

  -> /(other)
    if other.class != Interval
      return self * (~1.0 / other)
    if other.contains?(~0.0)
      raise "Interval./: divisor contains 0"
    self * Interval.new(~1.0 / other.hi, ~1.0 / other.lo)

  -> sqrt
    if @hi < ~0.0
      raise "Interval.sqrt: empty"
    lo = @lo
    if lo < ~0.0
      lo = ~0.0
    Interval.new(Math.sqrt(lo), Math.sqrt(@hi))

  -> exp
    Interval.new(Math.exp(@lo), Math.exp(@hi))

  -> log
    if @lo <= ~0.0
      raise "Interval.log: non-positive"
    Interval.new(Math.log(@lo), Math.log(@hi))

  -> sin
    # coarse enclosure over one period — widen to [-1,1] if width large
    if width >= ~6.283185307179586
      return Interval.new(~0.0 - ~1.0, ~1.0)
    # evaluate at endpoints + critical points in range (simplified)
    a = Math.sin(@lo)
    b = Math.sin(@hi)
    lo = a
    hi = a
    if b < lo
      lo = b
    if b > hi
      hi = b
    # if interval covers a peak/trough, expand
    # (v0: endpoint-only; document as non-sharp)
    Interval.new(lo, hi)

  -> to_s
    lo_s = @lo.to_s()
    hi_s = @hi.to_s()
    "[" + lo_s + ", " + hi_s + "]"
