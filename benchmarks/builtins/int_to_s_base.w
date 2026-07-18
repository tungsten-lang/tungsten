# Microbenchmark: Integer#to_s(base). Output: "int_to_s_base <ns/op> <checksum>".
n = 1_000_000
acc = 0 ## i64
t0 = clock()
i = 1
while i <= n
  acc += (i & 0xFFFFF).to_s(16).size
  acc += (i & 0xFFF).to_s(2).size
  i += 1
t1 = clock()
<< "int_to_s_base " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
