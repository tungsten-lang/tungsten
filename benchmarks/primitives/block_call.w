# primitive: block_call — 100000000 ops
chk = 0 ## i64
cap = 12345 ## i64
blk = ->(x) x ^ cap
n = 100000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
t0 = clock
i = 0 ## i64
while i < n
  chk = chk ^ blk(i)
  i = i + 1
t1 = clock
<< "ops: [n]"
<< chk
<< "elapsed: [t1 - t0]s"
