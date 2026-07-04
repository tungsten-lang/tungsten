# `-> new(@x, @y) ro` — trailing ro/rw on an @-binding constructor generates
# accessors for the bound fields (README's Point example).
+ Point
  -> new(@x, @y) ro

  -> sum
    @x + @y

+ Counter
  -> new(@n) rw

p = Point.new(3, 4)
<< p.x
<< p.y
<< p.sum
c = Counter.new(10)
c.n = c.n + 5
<< c.n
