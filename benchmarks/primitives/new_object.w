+ Pt
  -> new(@x, @y)
    self
  -> x
    @x

-> new_object_churn(n)
  chk = 0 ## i64
  i = 0 ## i64
  while i < n
    # Keep the allocation in a function-local scope. A top-level `o` is a
    # global by definition and measures an escaping object instead.
    o = Pt.new(i, chk)
    chk = chk ^ o.x
    i = i + 1
  chk

Tungsten.PROTECT_THE_CORE!
Tungsten.LOCK_THE_DOORS!

# primitive: new_object — 10000000 ops
n = 10000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
t0 = clock
chk = new_object_churn(n)
t1 = clock
<< "ops: [n]"
<< chk
<< "elapsed: [t1 - t0]s"
