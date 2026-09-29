# In a T=f32 specialization, a local taken from a typed-array load and then
# used in arithmetic emits invalid LLVM IR: "'%tN' defined with type 'i64'
# but expected 'float'" (the local is stored boxed, then read as a raw
# float). `a0 = a[0] ## T`, or using `a[0]` directly, compiles fine. The
# f64 specialization is unaffected.
+ Box<T>
  - data
    T v[2]

  -> new(@v ## T[2])

  -> f
    a = @v
    a0 = a[0]
    a0 * ~2.0

<< "expect 3, got " << Box<f32>.new([~1.5, ~2.0] ## f32[2]).f
