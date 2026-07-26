# primitive: int_add — 300000000 ops
s = 1 ## i64
n = 300000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
t0 = clock
i = 0 ## i64
while i < n
  s = s + (s ^ i)
  i = i + 1
t1 = clock
<< "ops: [n]"
<< s
<< "elapsed: [t1 - t0]s"
