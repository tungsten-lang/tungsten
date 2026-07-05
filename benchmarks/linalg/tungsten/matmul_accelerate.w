# Tungsten matmul benchmark — dispatches to Apple Accelerate's
# cblas_sgemm via the core/blas wrapper. This is the same code path
# as c-accelerate / python-numpy / swift-accelerate — Tungsten just
# hands raw float pointers to the AMX-tuned kernel and gets
# BLAS-class performance.

use core/blas

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = f32_array(size)
b = f32_array(size)
c = f32_array(size)

# Deterministic fill — matches the C / Rust / Python / Swift harnesses.
i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

# Warm up.
sgemm(a, b, c, n, n, n)

# Timed loop — K matmuls inside one clock_gettime region.
t0 = clock()
iter = 0
while iter < k_iters
  sgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-accelerate\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
