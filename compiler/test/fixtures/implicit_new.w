# Constructor sugar (Point(...) = Point.new(...)) and implicit construction
# from the receiver's class: a one-param method called with N>1 args wraps
# them in receiver.class.new when the constructor arity matches.
+ Point
  -> new(@x, @y, @z) ro

  -> distance(other)
    dx = (@x - other.x).to_f
    dy = (@y - other.y).to_f
    dz = (@z - other.z).to_f
    Math.sqrt(dx * dx + dy * dy + dz * dz)

p = Point(3, 4, 5)
<< p.x
<< p.distance(Point(0, 0, 0))
<< p.distance(2, 3, 4)
