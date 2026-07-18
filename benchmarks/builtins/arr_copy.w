# Microbenchmark: Array#copy(start, len). Output: "arr_copy <ns/op> <checksum>".
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
  c = arr.copy(8, 32)
  acc += c.size + c[0]
  i += 1
t1 = clock()
<< "arr_copy " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
