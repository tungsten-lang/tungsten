k = ARGV[0].to_i

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
