# Microbenchmark: String#swapcase. Output: "str_swapcase <ns/op> <checksum>".
n = 1_000_000
strings = ["hello World FROM tungsten Compiler", "a", "", "mIxEd CaSe StRiNg wItH sOmE lEnGtH"]
acc = 0 ## i64
t0 = clock()
i = 0
while i < n
  acc += strings[i & 3].swapcase.size
  i += 1
t1 = clock()
<< "str_swapcase " << ((t1 - t0) * ~1000000000.0 / n) << " " << acc
