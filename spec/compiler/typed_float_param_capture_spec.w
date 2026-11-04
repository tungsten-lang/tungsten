# Typed float parameters captured by blocks keep their values (compiled and interpreted).
# (2026-11-04, AV pipeline: "331 of 2,822,000 limiter gains differ on a Thread.new path".)
# A typed function's float parameter arrives boxed. When a block (an iterator
# block, a Thread.new body) captured it, the prologue spilled the BOXED bits
# into the capture slot, while every reader -- the function body and the block
# alike -- loads a machine-float variable's slot as a raw double. The NaN-box
# bias (2^48) landed in the mantissa: 0.8 read back as 0.83125, -1.8 as
# -1.8625, so a limiter ceiling passed into a typed fn that threaded its work
# was ~4% high and most of its gains came out 1.0.
#
# Run: bin/tungsten -o /tmp/tfpc spec/compiler/typed_float_param_capture_spec.w && /tmp/tfpc

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# the parameter captured by an iterator block, read inside it
-> block_reads(x) (f64) f64
  r = [1].map ->(k)
    x
  r[0]

# ... and read by the function body itself once it lives in a capture slot
-> body_reads(x) (f64) f64
  r = [1].map ->(k)
    x + ~1.0
  x

# a Thread.new body (the AV leveller's shape: a typed fn that threads its work)
-> thread_reads(x, y) (f64 f64) f64
  t = Thread.new ->
    x * y
  t.join

# f32 parameters take the same path through a "float" slot
-> block_reads32(x) (f32) f64
  r = [1].map ->(k)
    x ## f64
  r[0]

# mixed signature: int, typed array and float params, the float one captured
-> mixed(n, a, c) (i64 f64[] f64) f64
  t = Thread.new ->
    s = ~0.0
    i = 0
    while i < n
      v = a[i]
      s = s + (v > c ? c : v)
      i += 1
    s
  t.join

check("iterator block reads 0.8", block_reads(~0.8), ~0.8)
check("iterator block reads -1.8", block_reads(~-1.8), ~-1.8)
check("iterator block reads 1e-300", block_reads(~1e-300), ~1e-300)
check("function body reads its captured param", body_reads(~0.8055523148770532), ~0.8055523148770532)
check("Thread.new body reads both params", thread_reads(~0.8, ~-1.5), ~0.8 * ~-1.5)
check("f32 param through a float slot", block_reads32(~0.8 ## f32), (~0.8 ## f32) ## f64)
a = f64[4]
a[0] = ~0.5
a[1] = ~0.9
a[2] = ~0.81
a[3] = ~0.1
check("typed fn threads its work with a captured ceiling", mixed(4, a, ~0.8), ~0.5 + ~0.8 + ~0.8 + ~0.1)
