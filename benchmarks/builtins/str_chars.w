# Microbenchmark: String#chars. Output: "str_chars <ns/op> <checksum>".
n = 500_000
strings = ["hello world", "abé🎉", "x", "the quick brown fox"]
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += strings[i & 3].chars.size
  i += 1
t1 = clock()
<< "str_chars " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
