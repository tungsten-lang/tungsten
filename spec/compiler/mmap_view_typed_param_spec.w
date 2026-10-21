# Regression (2026-10-21): an mmap view passed as a typed-array parameter.
# Mmap#as_u8 (and the other as_* views) return a BigArray, the i64-field
# array tier, while a body compiled for `(u8[])` indexes a WArray. The
# parameter guard (w_check_array_ebits) let a same-width BigArray straight
# through, so the callee read the BigArray header as a WArray and segfaulted.
# The guard now hands the callee a zero-copy WArray view of the same bytes.
# It also decodes a BigArray's signed element code, so an f64 view reaches an
# `(f64[])` parameter instead of failing the width check.

-> check(name, got, want)
  if got == want
    << "PASS " + name
  else
    << "FAIL " + name + " got " + got.to_s() + " want " + want.to_s()
    exit 1

-> byte_sum(b, n) (u8[] i64) i64
  s = 0
  i = 0
  while i < n
    s += b[i]
    i += 1
  s

-> byte_at(b, i) (u8[] i64) i64
  b[i]

-> f64_sum(v, n) (f64[] i64) f64
  s = ~0.0
  i = 0
  while i < n
    s += v[i]
    i += 1
  s

tmp = Tempfile.new("tungsten-mmap-param")
path = tmp.path
tmp.close!()
File.write(path, "ABC")
m = File.mmap(path)
view = m.as_u8
check("u8 view sum", byte_sum(view, view.size), 198)
check("u8 view index", byte_at(view, 2), 67)

# The same view in a loop reuses one cached header.
total = 0
k = 0
while k < 1000
  total += byte_at(view, k % 3)
  k += 1
check("u8 view in a loop", total, 65999)
m.close

# 1.5, 2.25 and 4.0 as little-endian IEEE doubles.
raw = u8[24]
raw[6] = 248
raw[7] = 63
raw[14] = 2
raw[15] = 64
raw[22] = 16
raw[23] = 64
fpath = path + ".f64"
File.write_bytes(fpath, raw)
fm = File.mmap(fpath)
fview = fm.as_f64
check("f64 view sum", f64_sum(fview, fview.size), ~7.75)
fm.close
File.rm(path)
File.rm(fpath)
