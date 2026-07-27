# primitive: array_mod — wraparound (masked-index) array read: `tab[i & 1023]`
# in a flat loop. This shape used to mis-peel under LLVM's loop vectorizer
# (~3.8B ops/s); lowering now stamps `llvm.loop.vectorize.enable=false` on
# masked-index loop latches (see lowering/analysis.w loop_masked_array_index?),
# letting the unroller emit a 4-accumulator interleave → ~10.4B, matching C.
# Guards that treatment: losing the stamp drops this primitive to ~4B.
-> run(n) (i64) i64
  tab = SmallArray<i64, 1024>.new
  j = 0 ## i64
  while j < 1024
    tab[j] = j * 2654435761
    j = j + 1
  t0 = clock
  chk = 0 ## i64
  i = 0 ## i64
  while i < n
    chk = chk ^ tab[i & 1023]
    i = i + 1
  t1 = clock
  << "ops: [n]"
  << chk
  << "elapsed: [t1 - t0]s"
  chk
n = 300000000 ## i64
__ev = env("BENCH_ITERS")
if __ev != nil && __ev != ""
  n = __ev.to_i() ## i64
run(n)
