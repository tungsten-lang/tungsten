# Microbenchmark: Array#reverse. Output: "arr_reverse <ns/op> <checksum>".
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
  r = arr.reverse
  acc += r[0] + r.size
  i += 1
t1 = clock()
<< "arr_reverse " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
