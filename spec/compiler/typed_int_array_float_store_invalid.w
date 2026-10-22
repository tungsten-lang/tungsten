# spec: compiled-rejects -- expected int, got double
# spec: interpreter-rejects -- expected int, got double
# A float stored into an integer typed array is an error on every engine. The
# compiled inline store in typed code used to write the boxed double's bits
# instead (a u8 slot read 205 for 99.7), while the interpreter and the boxed
# compiled store raised. The studio engine's "u8 cast reads 0" bug was this
# store, reached through a misparsed `a[i] = v ## i64`.

-> tia_store(out, v) (u8[] f64) i64
  out[0] = v
  0

px = u8[1]
tia_store(px, ~99.7)
<< "stored " + px[0].to_s
