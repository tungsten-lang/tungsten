# Microbenchmark: Integer#chr. Output: "int_chr <ns/op> <checksum>".
n = 2_000_000
acc = 0 ## i64
t0 = clock()
i = 1
while i <= n
  acc += (i & 0x1FFFF).chr.size
  i += 1
t1 = clock()
<< "int_chr " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
