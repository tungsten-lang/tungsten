# Typed functions whose locals, temporaries and calls must stay raw machine
# values (no __w_*_fast boxed helpers). Checked by scripts/test-typed-raw-wire.sh.

-> fa(n) (i64) i64
  a = 1 << n
  a + 1
-> fc(n) (i64) i64
  one = 1 ## i64
  a = one << n
  a + 1
-> gc(n) (i64) i64
  v = n | (n << 3)
  v + 1
-> hc(n, a) (i64 i32[]) i64
  v = n > 2 ? a[1] : 0
  v + 1
-> band(a, b) (i64 i64) i64
  (a & b) + (a ^ 7) + (b | 3)
-> mixf(x, g) (f64 i64) f64
  y = x * g
  y + 1
-> elemf(a, i, s) (i32[] i64 f64) f64
  a[i] * s
-> elemf2(a, i) (u8[] i64) f64
  a[i] * ~0.5
-> loopshl(n, k) (i64 i64) i64
  s = 0 ## i64
  i = 0
  while i < k
    s += (1 << n) - 1
    i += 1
  s
-> early(d, n) (u8[] i64) i64
  return 0 if n == 0
  (d[0] * 7 + n) & ((1 << n) - 1)
-> clip(v) (i64) i64
  v < 0 ? 0 : (v > 255 ? 255 : v)
-> useclip(a, n) (i32[] i64) i64
  s = 0
  i = 0
  while i < n
    s += clip(a[i])
    i += 1
  s
-> wid(a) (i32[]) i64
  clip(a[0])
-> tern2(a, i) (u16[] i64) i64
  x = i > 0 ? a[i] : a[0] + 1
  x * 2
-> flt(a) (f64[]) f64
  t = a[0] * 2
  t + a[1]
a = i32[4]
u = u8[4]
w = u16[4]
fa_ = f64[4]
<< fa(3) + fc(3) + gc(3) + hc(3, a) + band(5, 6) + loopshl(3, 10) + early(u, 3) + useclip(a, 4) + wid(a) + tern2(w, 1)
<< mixf(~0.5, 3) + elemf(a, 1, ~0.5) + elemf2(u, 1) + flt(fa_)
