# primitive: array_set — 300000000 ops
chk = 0 ## i64
tab = i64[1024]
n = 300000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  tab[i & 1023] = i ^ chk
  chk = chk + 1
  i = i + 1
t1 = clock
<< "ops: 300000000"
<< chk
<< "elapsed: [t1 - t0]s"
