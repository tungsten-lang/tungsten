# primitive: array_set_heap (HEAP) — sequential element write over a heap-
# allocated typed array `i64[1024]` (WArray). Same access pattern as array_set
# (stack) so the two lines are a direct heap-vs-stack comparison.
-> run(reps) (i64) i64
  tab = i64[1024]
  t0 = clock
  chk = reps ## i64
  r = 0 ## i64
  while r < reps
    k = 0 ## i64
    while k < 1024
      tab[k] = chk ^ k
      chk = chk + 1
      k = k + 1
    r = r + 1
  t1 = clock
  out = chk ^ tab[0] ^ tab[1023]
  ops = reps * 1024
  << "ops: [ops]"
  << out
  << "elapsed: [t1 - t0]s"
  out
reps = 976562 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  tmp = __ev.to_i() ## i64
  reps = tmp / 1024
if reps < 1
  reps = 1
run(reps)
