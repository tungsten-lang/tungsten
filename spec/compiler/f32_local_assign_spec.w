# spec: compiled
# A local first assigned an f32 value (an f32[] element, or a call that
# returns an `## f32` cast) and later used in f32 arithmetic was kept as a
# boxed register while its type said :f32, so reads used the boxed bits as a
# float and clang rejected the module ("'%tN' defined with type 'i64' but
# expected 'float'"). Such a local now gets a raw float slot; an existing float
# slot takes the converted value too.
#
# Run:
#   bin/tungsten spec/compiler/f32_local_assign_spec.w

-> halve_all(src, out, n) (f32[] f32[] i64) i64
  i = 0
  while i < n
    l = src[i]
    l = l * (~0.5 ## f32)
    out[i] = l
    i += 1
  n

-> retype(a) (f32[]) i64
  t = a[0]
  a[1] = a[1] - t
  t = ~0.0 - a[2]
  a[3] = a[3] - t
  0

-> to_f32(x)
  (x) ## f32

-> chain(a)
  p = to_f32(a ## f64)
  p = to_f32(p * ~1.5)
  p

-> check(name, ok)
  raise "FAIL " + name if !ok
  << "PASS " + name

src = f32[4]
src[1] = (~3.0 ## f32)
out = f32[4]
halve_all(src, out, 4)
check("f32[] element local", out[1] == ~1.5)
x = f32[4]
x[0] = (~1.0 ## f32)
x[1] = (~5.0 ## f32)
x[2] = (~2.0 ## f32)
x[3] = (~1.0 ## f32)
retype(x)
check("f32 local retyped by f64 arithmetic", x[1] == ~4.0 && x[3] == ~3.0)
check("untyped f32-returning call", chain(3) == ~4.5)
<< "f32_local_assign_spec: all passed"
