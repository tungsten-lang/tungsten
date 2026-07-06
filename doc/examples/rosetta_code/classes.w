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

## expect skip compiled-only for now — the Ruby interpreter (which runs this harness) can't execute it; try `bin/tungsten classes.w`
## expect stdout
## (3, 4)
## Distance: 5
