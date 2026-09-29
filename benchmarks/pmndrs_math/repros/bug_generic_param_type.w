# A generic type in a param type list, `(Vec3<T>)`, makes the method return
# the class instead of running its body.
+ Probe<T> < Vec3<T>
  - data
    T components[3]

  -> dot_g/1(Vec3<T>)
    b = @1.components
    a = @components
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

a = Probe<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3])
<< "expect 14, got " << a.dot_g(a)
