# File protocol v1: native-endian contiguous f64 input/output, element count.
# Python owns the temporary files. The mapping owns the borrowed input view;
# it stays alive until computation finishes. Output is independent storage.
use core/mmap

-> transform(values, count) (f64[] i64)
  result = f64[count]
  i = 0 ## i64
  while i < count
    x = values[i] ## f64
    result[i] = x * x + ~2.0 * x + ~1.0
    i += 1
  result

if ARGV.size() != 3
  raise "expected input path, output path, and element count"
n = ARGV[2].to_i() ## i64
if n < 1 || n > 2147483647
  raise "element count is outside the f64 array contract"
mapping = File.mmap(ARGV[0])
if mapping.size() != n * 8
  raise "input byte length does not match the element count"
values = ccall("tungsten_numpy_f64_view", mapping)
result = transform(values, n)
bytes = result.view(8)
if !write_file_bytes(ARGV[1], bytes)
  raise "could not write the complete output"
# Keep the owning array live through its borrowed byte-view write.
if result.size() != n
  raise "kernel returned the wrong element count"
mapping.close()
<< "tungsten-numpy-v1 " + n.to_s()
