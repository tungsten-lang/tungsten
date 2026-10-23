# A `*rest` method called with several arguments receives them all, on every
# engine. Implicit construction (a one-parameter method called with N > 1
# arguments wraps them in the receiver class's constructor:
# p.dist2(3, 4) ≡ p.dist2(Point.new(3, 4))) also fired for a single `*rest`
# parameter in the compiled runtime and the tree-walker, so `p.gather(1, 2)`
# on a class whose constructor takes two arguments got one Point instead of
# [1, 2] (2026-10-21). The Ruby implementation already excluded splats.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

+ Point
  -> new(@x, @y)

  ro :x
  ro :y

  -> dist2(other)
    dx = other.x - @x
    dy = other.y - @y
    dx * dx + dy * dy

  -> gather(*items)
    items

p = Point.new(0, 0)
# Implicit construction is a dispatch-time rule: compiled code rejects
# `p.dist2(3, 4)` when it knows p's class, so reach it through a value of
# unknown type.
held = [p]
check("implicit construction still wraps", held[0].dist2(3, 4), 25)
check("a held splat takes the arguments", held[0].gather(1, 2), [1, 2])
check("splat takes two arguments", p.gather(1, 2), [1, 2])
check("splat takes three arguments", p.gather(1, 2, 3), [1, 2, 3])
check("splat takes one argument", p.gather(7), [7])
check("splat takes none", p.gather(), [])
