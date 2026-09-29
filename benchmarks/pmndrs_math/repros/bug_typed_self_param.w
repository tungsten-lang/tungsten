# Typed `(Self)` param on a generic class: the exact-class guard's slow
# path still does T-typed loads on the argument's storage.
+ Probe<T> < Vec3<T>
  - data
    T components[3]

  -> dot_self/1(Probe)
    b = @1.components
    a = @components
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

a = Probe<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
e = Probe<f32>.new([~4.0, ~5.0, ~6.0] ## f32[3])
f = Vec3<i64>.new([4, 5, 6] ## i64[3])
m = ARGV[0]
if m == "f32"
  << "expect 32, got " << a.dot_self(e)
if m == "i64"
  << "expect 32, got " << a.dot_self(f)
