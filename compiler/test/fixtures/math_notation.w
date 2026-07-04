# README math notation: prime properties (x'), Δ deltas, √, .sq, <> swap.
# Carries a checked-in .expected — the Ruby engine runs this too but its
# display formats differ (5.0 vs 5, 0.25e0 vs 0.25), so compiled output is
# the pinned ground truth.
+ Point
  -> new(@x, @y, @z) ro

  -> distance/1
    dx = x - x'
    dy = y - y'
    dz = z - z'
    (dx.sq + dy.sq + dz.sq).sqrt

  -> distance2/1
    √(Δx² + Δy² + Δz²)

p = Point(3, 4, 0)
q = Point(0, 0, 0)
<< p.distance(q)
<< p.distance2(q)

a = 1
b = 2
a <> b
<< a
<< b

<< 5.sq
<< 0.5.sq
<< √16
