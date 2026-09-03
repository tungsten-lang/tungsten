## parity xfail == on two distinct instances of a user class with equal fields is true interpreted (structural) but false compiled (identity)
# Classes: default == between instances.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Point
  ro :x
  ro :y
  -> new(@x, @y)

a = Point.new(1, 2)
b = Point.new(1, 2)
<< "eq.distinct [a == b]"
<< "eq.same [a == a]"
<< "eq.diff [a == Point.new(2, 1)]"
