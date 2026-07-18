# Microbenchmark: Array#delete_at (mutating middle-shift). Output: "arr_delete_at <ns/op> <checksum>".
# Rebuild the array each iteration since delete_at mutates; measure the delete only.
n = 200_000
acc = 0 ## i64
t_del = ~0.0
i = 0
while i < n
  arr = []
  k = 0
  while k < 32
    arr.push(k * 3)
    k += 1
  t0 = clock()
  removed = arr.delete_at(8)
  t1 = clock()
  t_del += t1 - t0
  acc += removed + arr.size
  i += 1
<< "arr_delete_at " << (t_del * ~1000000000.0 / n) << " " << acc
