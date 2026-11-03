# `## T` binds more loosely than every operator and converts the value of the
# whole expression before it: in `<< e ## i64` that is the printed `e`, in
# `x = e ## i64` the right-hand side, in `(e) ## i64` the group. Float
# arithmetic is truncated once, after it is computed.
#
# Cross-engine parity spec (scripts/parity.sh).

a = ~0.279
<< a * ~48000.0 ## i64
<< (a * ~48000.0) ## i64
<< ~2.5 * ~3.0 ## i64
b = a * ~48000.0 ## i64
<< b
<< b + 1
c = (~2.5 + ~0.75) ## i32
<< c
<< (~0.5 * ~1.5) ## f32
-> samples(t0) (f64) i64
  (t0 * ~48000.0) ## i64
<< samples(~1.484)
<< (((a * ~1000.0) ## i64) * 48) ## i64
n = 6 ## i64
<< n * 7 ## i64
<< (n << 3) ## i64
