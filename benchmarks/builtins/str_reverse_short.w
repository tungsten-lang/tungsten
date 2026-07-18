# Microbenchmark: String#reverse on short (inline-length) strings.
n = 2_000_000
strings = ["ab", "hello", "x", "café"]
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += strings[i & 3].reverse.size
  i += 1
t1 = clock()
<< "str_reverse_short " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
