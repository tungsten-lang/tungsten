# Microbenchmark: Array#drop. Output: "arr_drop <ns/op> <checksum>".
n = 500_000
arr = []
k = 0
while k < 64
  arr.push(k * 7)
  k += 1
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  d = arr.drop(32)
  acc += d.size + d[0]
  i += 1
t1 = clock()
<< "arr_drop " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
