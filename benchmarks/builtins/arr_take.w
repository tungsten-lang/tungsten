# Microbenchmark: Array#take. Output: "arr_take <ns/op> <checksum>".
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
  t = arr.take(32)
  acc += t.size + t[31]
  i += 1
t1 = clock()
<< "arr_take " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
