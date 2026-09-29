# Subclass bodies see an inherited `- data` field as untyped: `a[0]` below
# lowers to a dynamic `[]` call (w_method_call_cached) plus boxed
# __w_mul_fast/__w_add_fast, unless the subclass re-declares the block.
+ Plain<T> < Vec3<T>
  -> ls
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

+ Redeclared<T> < Vec3<T>
  - data
    T components[3]

  -> ls
    a = @components
    a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

<< Plain<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3]).ls
<< Redeclared<f64>.new([~1.0, ~2.0, ~3.0] ## f64[3]).ls
