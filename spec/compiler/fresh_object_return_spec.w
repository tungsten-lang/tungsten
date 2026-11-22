# spec: compiled -- exercises the ownership pass's fresh heap results
# compiler/lib/ownership.w fresh_heap_returns: a function whose every return
# is a guarded `Cls.new(...)` (construct_producer_class: the receiver is the
# guarded class and the initializer never stores self) returns a fresh
# instance. A caller that only reads the result (a call whose escape summary
# keeps nothing, or a guarded method call the class makes certain) frees it
# at scope end. Every shape that must keep the instance alive is checked
# first, then the memory of a loop that builds and drops instances is bounded.

-> check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

+ Pt
  -> new(@x, @y)
  ro :x
  ro :y
  -> sum
    @x + @y

# Initializer that keeps self: never fresh.
REGISTRY = []
+ Tracked
  -> new(@v)
    REGISTRY.push(self)
  ro :v

-> make_pt(i)
  Pt.new(i, i + 1)

-> make_tracked(i)
  Tracked.new(i)

# Returns a shared instance on one path: never fresh.
SHARED = [Pt.new(100, 200)]
-> maybe_shared(i)
  if i % 2 == 0
    return SHARED[0]
  Pt.new(i, i)

# Stores the instance before returning it: never fresh.
KEPT = []
-> make_and_keep(i)
  p = Pt.new(i, i)
  KEPT.push(p)
  p

-> read_xy(p)
  p.x + p.y

+ Holder
  -> new
    @items = []
  -> keep(p)
    @items.push(p)
  -> slot(p)
    @last = p
  ro :items
  ro :last

# --- the result escapes: every one must stay valid -------------------------
stored = []
i = 0
while i < 50
  stored.push(make_pt(i))
  i += 1
check("instances stored in an array stay valid", stored[49].x == 49 && stored[0].y == 1)

h = Holder.new
i = 0
while i < 50
  p = make_pt(i)
  h.keep(p)
  h.slot(p)
  i += 1
check("instances stored through ivars stay valid", h.items[10].y == 11 && h.last.x == 49)

-> capture(i)
  p = make_pt(i)
  f = -> ()
    p.x * 2
  f

closures = []
i = 0
while i < 20
  closures.push(capture(i))
  i += 1
check("instances captured by closures stay valid", closures[7].call() == 14)

-> pass_through(i)
  p = make_pt(i)
  junk = read_xy(p)
  p
returned = pass_through(5)
check("an instance returned by the caller stays valid", returned.x == 5 && returned.y == 6)

i = 0
while i < 20
  t = make_tracked(i)
  i += 1
check("an initializer that keeps self keeps its instances valid", REGISTRY.size == 20 && REGISTRY[19].v == 19)

i = 0
total = 0
while i < 20
  q = maybe_shared(i)
  total += read_xy(q)
  i += 1
check("a function that may return a shared instance never frees it", SHARED[0].x == 100 && SHARED[0].y == 200)

i = 0
while i < 20
  k = make_and_keep(i)
  total += read_xy(k)
  i += 1
check("a function that keeps its instance never hands it over fresh", KEPT.size == 20 && KEPT[19].x == 19)

# --- the result is only read: freed each iteration -------------------------
-> drop_loop(n)
  acc = 0
  i = 0
  while i < n
    p = make_pt(i)
    acc += read_xy(p)
    i += 1
  acc

-> method_loop(n)
  acc = 0
  i = 0
  while i < n
    p = make_pt(i)
    acc += p.sum
    i += 1
  acc

check("read-only loop computes", drop_loop(1000) == 1000000)
check("method-call loop computes", method_loop(1000) == 1000000)
# drop_loop's instances are not freed yet: read_xy calls accessors on an
# untyped parameter, a dynamic send whose escape summary keeps the receiver.
# method_loop's `p.sum` is a closed-world direct call to Pt#sum, whose
# summary keeps nothing, so each instance is freed at the end of its
# iteration.
m0 = Process.memory_footprint
check("method-call loop over a million instances", method_loop(1000000) == 1000000000000)
grown = (Process.memory_footprint - m0) / 1048576
check("instances built and dropped are freed", grown < 16)
