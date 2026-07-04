use io
use argv

+ Point
  rw :x, :y

  -> new(@x=0, @y=0)
  -> to_s "Point at [x],[y]"

+ Circle < Point
  rw :r

  -> new(@x=0, @y=0, @r=0)
  -> to_s "Circle at [x],[y] with radius [r]"

p Point.new

p = Point.new(1, 2)
io p
   p.x

p.y += 1
io p

# Create a circle
c = Circle.new(4,5,6)

# copy it
d = c.dup
d.r = 7.5

put  c
puts d

### with out ###

out p
    p.x

    c
    d

### with log ###

log p
    p.x

    c
    d

err msg

### with << ###

<< p
   p.x

   c
   d

<! msg
<~ msg # debug

### with _< ###

_< p
   p.x

   c
   d

_! err

### with <= ###

<= p
   p.x

   c
   d

### with ~~ ###

~~ p
   p.x

   c
   d

   "Hello World"

## expect skip currently unsupported in this runtime
