# Microbenchmark: Integer#to_s (decimal). Output: "int_to_s <ns/op> <checksum>".
n = 2_000_000
acc = 0 ## i64
t0 = clock()
i = 1
while i <= n
  acc += i.to_s.size
  acc += (0 - i).to_s.size
  i += 1
t1 = clock()
<< "int_to_s " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
