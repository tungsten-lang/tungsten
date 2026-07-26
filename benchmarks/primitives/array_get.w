# primitive: array_get — 300000000 ops
chk = 0 ## i64
tab = i64[1024]
j = 0 ## i64
while j < 1024
  tab[j] = j * 2654435761
  j = j + 1
n = 300000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ tab[i & 1023]
  i = i + 1
t1 = clock
<< "ops: 300000000"
<< chk
<< "elapsed: [t1 - t0]s"
