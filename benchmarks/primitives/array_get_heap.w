# primitive: array_get_heap (HEAP) — sequential element read over a heap-
# allocated typed array `i64[1024]` (a WArray: 24-byte header + separate slots
# malloc). Same access pattern as array_get (stack) so the two lines are a
# direct heap-vs-stack comparison. Element-read throughput is representation-
# independent once the slots base is hoisted out of the loop; the stack win is
# in ALLOCATION (see new_array), not access.
-> run(reps) (i64) i64
  tab = i64[1024]
  j = 0 ## i64
  while j < 1024
    tab[j] = j * 2654435761 + reps
    j = j + 1
  t0 = clock
  chk = reps ## i64
  r = 0 ## i64
  while r < reps
    k = 0 ## i64
    while k < 1024
      chk = chk ^ (tab[k] + r)
      k = k + 1
    r = r + 1
  t1 = clock
  ops = reps * 1024
  << "ops: [ops]"
  << chk
  << "elapsed: [t1 - t0]s"
  chk
reps = 976562 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  tmp = __ev.to_i() ## i64
  reps = tmp / 1024
if reps < 1
  reps = 1
run(reps)
