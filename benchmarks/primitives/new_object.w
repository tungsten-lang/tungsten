+ Pt
  -> new(@x, @y)
    self
  -> x
    @x

# primitive: new_object — 10000000 ops
chk = 0 ## i64
n = 10000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
t0 = clock
i = 0 ## i64
while i < n
  o = Pt.new(i, chk)
  chk = chk ^ o.x
  i = i + 1
t1 = clock
<< "ops: [n]"
<< chk
<< "elapsed: [t1 - t0]s"
