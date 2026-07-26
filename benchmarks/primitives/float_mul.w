# primitive: float_mul — 20000000 ops
f = 0.5 ## f64
c1 = 3.9 ## f64
c2 = 1.0 ## f64
n = 20000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  f = c1 * f * (c2 - f)
  i = i + 1
t1 = clock
<< "ops: 20000000"
<< f
<< "elapsed: [t1 - t0]s"
