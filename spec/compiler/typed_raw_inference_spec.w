# Typed code infers raw machine types where the old inference boxed:
# - `1 << n` with a machine-int amount is a machine shift (wrapping i64);
# - a ternary over a narrow typed-array element and a literal is a raw i64;
# - f64 (or a typed-array element) times an integer is raw f64 arithmetic;
# - a narrow element (i32/u16/u8) passed to an i64 or f64 parameter widens.
# Values here agree on every engine; scripts/test-typed-raw-wire.sh checks
# the compiled WIRE has no boxed helpers.

$failures = 0

-> check(label, got, want)
  if got != want
    << "FAIL [label]: got [got], want [want]"
    $failures = $failures + 1

-> shl_local(n) (i64) i64
  a = 1 << n
  a + 1

-> shl_mask(d, n) (u8[] i64) i64
  (d[0] * 7 + n) & ((1 << n) - 1)

-> shl_chain(n) (i64) i64
  v = n | (n << 3)
  v + 1

-> pick(n, a) (i64 i32[]) i64
  v = n > 2 ? a[1] : 0
  v + 1

-> pick16(a, i) (u16[] i64) i64
  x = i > 0 ? a[i] : a[0] + 1
  x * 2

-> scale(x, g) (f64 i64) f64
  y = x * g
  y + 1

-> elem_scale(a, i, s) (i32[] i64 f64) f64
  a[i] * s

-> flt(a) (f64[]) f64
  t = a[0] * 2
  t + a[1]

-> clip(v) (i64) i64
  v < 0 ? 0 : (v > 255 ? 255 : v)

-> half(v) (f64) f64
  v * ~0.5

-> clip_sum(a, n) (i32[] i64) i64
  s = 0
  i = 0
  while i < n
    s += clip(a[i])
    i += 1
  s

-> widen_f(a) (u8[]) f64
  half(a[0])

a = i32[4]
a[0] = -5
a[1] = 300
a[2] = 7
a[3] = 255
u = u8[2]
u[0] = 9
w = u16[3]
w[0] = 4
w[2] = 65535
f = f64[2]
f[0] = ~1.5
f[1] = ~0.25

check("shl local", shl_local(10), 1025)
check("shl 62", shl_local(62), 4611686018427387905)
check("shl mask", shl_mask(u, 4), 3)
check("shl chain", shl_chain(5), 46)
check("ternary i32 then", pick(3, a), 301)
check("ternary i32 else", pick(1, a), 1)
check("ternary u16 then", pick16(w, 2), 131070)
check("ternary u16 else", pick16(w, 0), 10)
check("f64 times int", scale(~0.5, 3), ~2.5)
check("i32 elem times f64", elem_scale(a, 2, ~0.5), ~3.5)
check("f64 elem times int", flt(f), ~3.25)
check("widened i32 arg", clip_sum(a, 4), 517)
check("widened u8 to f64", widen_f(u), ~4.5)

if $failures > 0
  exit(1)
<< "PASS typed raw inference"
