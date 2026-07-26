-> mix(a, b) (i64 i64) i64
  (a * 2654435761) ^ (b >> 3)

# primitive: fn_call — 200000000 ops
chk = 0 ## i64
n = 200000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ mix(i, chk)
  i = i + 1
t1 = clock
<< "ops: 200000000"
<< chk
<< "elapsed: [t1 - t0]s"
