# Microbenchmark: Array#uniq. Output: "arr_uniq <ns/op> <checksum>".
n = 200_000
arr = []
k = 0
while k < 64
  arr.push(k & 31)
  k += 1
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  u = arr.uniq
  acc += u.size + u[31]
  i += 1
t1 = clock()
<< "arr_uniq " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
