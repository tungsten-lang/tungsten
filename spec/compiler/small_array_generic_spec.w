# SmallArray<T, N> — source-level fixed-size small-array type. `SmallArray<T,N>.new`
# desugars (monomorphize.w rewrite_smallarray_generic_ctors) to the typed-array
# literal `T[N]`, which stack-promotes to a HEADERLESS raw [N x T] alloca when the
# var is a non-escaping local (SROA-able), and `.size` folds to the constant N.
# Const-int generic monomorphization (Stage 1) supplies the literal N.
#
# Run: `bin/tungsten -o /tmp/sag spec/compiler/small_array_generic_spec.w && /tmp/sag`

-> check(name, ok)
  if ok
    << "PASS " + name
  else
    << "FAIL " + name
    exit 1

# i32: fill with i*i, sum, plus constant size
-> i32_sum
  buf = SmallArray<i32, 32>.new
  i = 0 ## i64
  while i < 32
    buf[i] = i * i
    i += 1
  s = 0 ## i64
  j = 0 ## i64
  while j < 32
    s += buf[j]
    j += 1
  s + buf.size
check("smallarray.i32_fill_sum_size", i32_sum == 10448)   # Σ i² (0..31) = 10416, + size 32

# i64 element type
-> i64_ends
  b = SmallArray<i64, 16>.new
  b[0] = 1000
  b[15] = 2000
  b[0] + b[15] + b.size
check("smallarray.i64", i64_ends == 3016)

# f64 element type
-> f64_pair
  f = SmallArray<f64, 8>.new
  f[0] = 1.5
  f[7] = 2.5
  f[0] + f[7]
check("smallarray.f64", f64_pair == 4.0)

# u8 element type + constant size
-> u8_ends
  u = SmallArray<u8, 64>.new
  u[0] = 200
  u[63] = 55
  u[0] + u[63] + u.size
check("smallarray.u8", u8_ends == 319)

# identity: SmallArray<i32,N> == i32[N] == SmallArray.new(:i32,N)
-> via_generic
  b = SmallArray<i32, 4>.new
  b[0] = 7
  b[3] = 9
  b[0] + b[3] + b.size
-> via_literal
  b = i32[4]
  b[0] = 7
  b[3] = 9
  b[0] + b[3] + b.size
check("smallarray.identity_literal", via_generic == via_literal)

# .size is the compile-time constant N (not a runtime header read)
-> just_size
  b = SmallArray<i32, 100>.new
  b.size
check("smallarray.size_is_const", just_size == 100)

# empty (N=0) is valid
-> empty_size
  b = SmallArray<i32, 0>.new
  b.size
check("smallarray.empty", empty_size == 0)
