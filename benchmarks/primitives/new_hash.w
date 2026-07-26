# primitive: new_hash — 10000000 ops
chk = 0 ## i64
n = 10000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  h = {}
  h["k"] = i
  chk = chk ^ h.size()
  i = i + 1
t1 = clock
<< "ops: 10000000"
<< chk
<< "elapsed: [t1 - t0]s"
