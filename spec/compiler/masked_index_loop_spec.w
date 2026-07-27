# Masked/wraparound index loops — `tab[i & 1023]`, `tab[i % 1000]` — get
# `llvm.loop.vectorize.enable=false` stamped on their latch (lowering/analysis.w
# loop_masked_array_index? → control_flow.w lower_while → emitter :br novec).
# LLVM's vectorizer mis-peels these ~2.6x slower than its own unroller; the
# metadata opts just those loops out. This spec pins CORRECTNESS of the stamped
# shapes (read, write, %-index, variable mask, heap array) — expected values
# verified against the unstamped compiler (HEAD differential, 2026-07-26).
#
# Run: `bin/tungsten -o /tmp/mil spec/compiler/masked_index_loop_spec.w && /tmp/mil`

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

# modular WRITE + read-back
-> wtest(n) (i64) i64
  tab = SmallArray<i64, 1024>.new
  chk = 0 ## i64
  i = 0 ## i64
  while i < n
    tab[i & 1023] = i ^ chk
    chk = chk + 1
    i = i + 1
  chk ^ tab[0] ^ tab[513]
check("masked.write_mod", wtest(10000019), 10000019)

# PERCENT wraparound read (non-power-of-2 period)
-> ptest(n) (i64) i64
  tab = SmallArray<i64, 1000>.new
  j = 0 ## i64
  while j < 1000
    tab[j] = j * 7 + 3
    j = j + 1
  chk = 0 ## i64
  i = 0 ## i64
  while i < n
    chk = chk ^ tab[i % 1000]
    i = i + 1
  chk
check("masked.percent_read", ptest(10000019), 200)

# mask by VARIABLE (hash-probe shape)
-> vtest(n, m) (i64 i64) i64
  tab = SmallArray<i64, 256>.new
  j = 0 ## i64
  while j < 256
    tab[j] = j * j
    j = j + 1
  h = 7 ## i64
  i = 0 ## i64
  while i < n
    h = (h * 31 + tab[h & m]) & 65535
    i = i + 1
  h
check("masked.var_mask_probe", vtest(1000003, 255), 38730)

# heap typed array modular read (WArray path benefits too: 2.2x)
-> htest(n) (i64) i64
  tab = i64[512]
  j = 0 ## i64
  while j < 512
    tab[j] = j * 2654435761
    j = j + 1
  chk = 0 ## i64
  i = 0 ## i64
  while i < n
    chk = chk ^ tab[i & 511]
    i = i + 1
  chk
check("masked.heap_mod_read", htest(10000019), 1961397738275)

# sequential loop stays UNSTAMPED (kept vectorized) — same numeric answer
# either way; pins that the detector doesn't misfire on unmasked indices.
-> stest(reps) (i64) i64
  tab = SmallArray<i64, 64>.new
  j = 0 ## i64
  while j < 64
    tab[j] = j * 3 + 1
    j = j + 1
  chk = 0 ## i64
  r = 0 ## i64
  while r < reps
    k = 0 ## i64
    while k < 64
      chk = chk ^ (tab[k] + r)
      k = k + 1
    r = r + 1
  chk
check("masked.sequential_untouched", stest(100003), 448)
