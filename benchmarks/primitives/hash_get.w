# primitive: hash_get — 40000000 ops
chk = 0 ## i64
hg = {}
keys = []
j = 0 ## i64
while j < 64
  k = "key" + j.to_s()
  keys.push(k)
  hg[k] = j * 3
  j = j + 1
n = 40000000 ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ hg[keys[i & 63]]
  i = i + 1
t1 = clock
<< "ops: 40000000"
<< chk
<< "elapsed: [t1 - t0]s"
