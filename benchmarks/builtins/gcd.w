# Microbenchmark: Integer#gcd. Output: "gcd <ns/op> <checksum>".
n = 3_000_000
acc = 0 ## i64
t0 = clock()
i = 1
while i <= n
  acc += (i | 1).gcd(1234567)
  i += 1
t1 = clock()
<< "gcd " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
