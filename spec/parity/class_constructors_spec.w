# Classes: constructors binding args to ivars, ro/rw accessors, to_s
# override, operator methods, class methods, default args, identity ==.
#
# Cross-engine parity spec (scripts/parity.sh).

+ Point
  ro :x
  ro :y
  -> new(@x, @y)
  -> to_s
    "([@x], [@y])"
  -> +(other)
    Point.new(@x + other.x, @y + other.y)
  -> dist2
    @x * @x + @y * @y

p = Point.new(3, 4)
<< "ro.x [p.x] ro.y [p.y]"
<< "to_s [p]"
<< "to_s.call [p.to_s]"
<< "concat " + p.to_s
<< "method [p.dist2]"
<< "op.plus [p + Point.new(1, 1)]"
<< "type [type(p)]"
<< "class [p.class]"
<< "is_a [p.is_a?(Point)]"
<< p

+ Counter
  rw :count
  -> new
    @count = 0
  -> incr
    @count += 1
    self

c = Counter.new
c.incr.incr
c.count = c.count + 10
<< "rw [c.count]"

+ Stack
  -> new
    @items = []
  -> push(x)
    @items.push(x)
    self
  -> pop
    @items.pop
  -> size
    @items.size
  -> empty?
    @items.size == 0

s = Stack.new
s.push(1).push(2).push(3)
<< "stack [s.pop] [s.size] [s.empty?]"

+ Config
  -> new(name, opts = {})
    @name = name
    @opts = opts
  -> name
    @name
  -> opt(k)
    @opts[k]

cfg = Config.new("svc", {port: 80})
<< "default.arg [cfg.name] [cfg.opt(:port)]"

+ Temp
  -> .freezing
    Temp.new(0)
  -> new(@deg)
  -> deg
    @deg

<< "class.method [Temp.freezing.deg]"
q = p
<< "eq.same [p == q]"
