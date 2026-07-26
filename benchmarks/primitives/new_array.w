# primitive: new_array — 15000000 ops
chk = 0 ## i64
n = 15000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  a = [i, i, i]
  chk = chk ^ a[i % 3]
  i = i + 1
t1 = clock
<< "ops: 15000000"
<< chk
<< "elapsed: [t1 - t0]s"
