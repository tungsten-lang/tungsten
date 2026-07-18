# Microbenchmark: String#reverse on a longer (slab/heap) string.
n = 1_000_000
s = "the quick brown fox jumps over the lazy dog 12345"
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += s.reverse.size
  i += 1
t1 = clock()
<< "str_reverse_long " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
