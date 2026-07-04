# Classes

+ Point
  -> new(@x, @y) ro

  -> distance/1
    dx = x - obj.x
    dy = y - obj.y
    ((dx * dx + dy * dy).to_f).sqrt

  -> to_s
    "([x], [y])"

p1 = Point(3, 4)
p2 = Point(0, 0)

<< p1
<< "Distance: [p1.distance(p2)]"

## expect skip currently unsupported in this runtime
