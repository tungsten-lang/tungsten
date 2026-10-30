# Classes

+ Point
  -> new(@x, @y) ro

  -> distance/1
    dx = x - @1.x
    dy = y - @1.y
    ((dx * dx + dy * dy).to_f).sqrt

  -> to_s
    "([x], [y])"

p1 = Point(3, 4)
p2 = Point(0, 0)

<< p1
<< "Distance: [p1.distance(p2)]"

## expect stdout
## (3, 4)
## Distance: 5
