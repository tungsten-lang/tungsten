# Microbenchmark: String#upcase. Output: "str_upcase <ns/op> <checksum>".
n = 1_000_000
strings = ["hello World FROM tungsten", "a", "", "mIxEd CaSe StRiNg oK"]
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += strings[i & 3].upcase.size
  i += 1
t1 = clock()
<< "str_upcase " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
