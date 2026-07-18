# Microbenchmark: Array#minmax. Output: "arr_minmax <ns/op> <checksum>".
n = 500_000
arr = []
k = 0
while k < 64
  arr.push((k * 37) & 255)
  k += 1
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  mm = arr.minmax
  acc += mm[0] + mm[1]
  i += 1
t1 = clock()
<< "arr_minmax " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
