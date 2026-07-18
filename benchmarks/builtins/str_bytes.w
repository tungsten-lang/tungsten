# Microbenchmark: String#bytes. Output: "str_bytes <ns/op> <checksum>".
n = 500_000
strings = ["hello world", "abc", "x", "the quick brown fox jumps"]
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += strings[i & 3].bytes.size
  i += 1
t1 = clock()
<< "str_bytes " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
