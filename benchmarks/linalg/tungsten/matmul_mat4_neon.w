k = ARGV[0].to_i

# Public Mat4 multiplication returns a fresh matrix and elements array. Keep
# this section bounded so the much larger iteration counts useful for the raw
# allocation-free kernel below do not turn into an ever-growing heap benchmark.
public_k = k
if public_k > 100000
  public_k = 100000

# Public API path: includes Mat4's synthesized Mat4/Vec4 overload dispatch and
# the boxed source-level arithmetic body. Keep this first so the benchmark can
# catch dispatch regressions independently of the raw runtime helper below.
pa = Mat4<f32>.new([
  1.0, 2.0, 3.0, 4.0,
  5.0, 6.0, 7.0, 8.0,
  9.0, 10.0, 11.0, 12.0,
  13.0, 14.0, 15.0, 17.0
] ## f32[16])
pb = Mat4<f32>.new([
  2.0, 0.0, 0.0, 0.0,
  0.0, 2.0, 0.0, 0.0,
  0.0, 0.0, 2.0, 0.0,
  0.0, 0.0, 0.0, 2.0
] ## f32[16])

pr = pa * pb
t0 = clock()
iter = 0
while iter < public_k
  pr = pa * pb
  iter = iter + 1
t1 = clock()

elapsed_ns = (t1 - t0) * ~1000000000.0
ns_per_call = elapsed_ns / public_k
<< "tungsten-public-mat4 ns/call:" << ns_per_call << "  iterations:" << public_k << "  checksum:" << pr.elements[0]

a = ccall("w_array_new_aligned", -32, 16) ## f32[]
b = ccall("w_array_new_aligned", -32, 16) ## f32[]
c = ccall("w_array_new_aligned", -32, 16) ## f32[]

i = 0
while i < 16
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  c[i] = ~0.0
  i = i + 1

# warm
ccall("w_mat4_mul_f32", a, b, c)

t0 = clock()
iter = 0
while iter < k
  ccall("w_mat4_mul_f32", a, b, c)
  iter = iter + 1
t1 = clock()

elapsed_ns = (t1 - t0) * ~1000000000.0
ns_per_call = elapsed_ns / k
gflops = ~128.0 * k / elapsed_ns

<< "tungsten-neon-mat4  ns/call:" << ns_per_call << "  GFLOPS:" << gflops

# Compare to sgemm at N=4
ccall("w_blas_sgemm_nn", a, b, c, 4, 4, 4)

t0 = clock()
iter = 0
while iter < k
  ccall("w_blas_sgemm_nn", a, b, c, 4, 4, 4)
  iter = iter + 1
t1 = clock()

elapsed_ns = (t1 - t0) * ~1000000000.0
ns_per_call = elapsed_ns / k
gflops = ~128.0 * k / elapsed_ns

<< "tungsten-accel-sgemm ns/call:" << ns_per_call << "  GFLOPS:" << gflops
