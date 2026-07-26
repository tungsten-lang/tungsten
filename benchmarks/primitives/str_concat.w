# primitive: str_concat — 1500000 ops
chk = 0 ## i64
pre = "n="
n = 1500000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  s2 = pre + i.to_s()
  chk = chk ^ s2.size()
  i = i + 1
t1 = clock
<< "ops: 1500000"
<< chk
<< "elapsed: [t1 - t0]s"
