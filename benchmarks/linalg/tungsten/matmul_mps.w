# Tungsten matmul benchmark — direct MPSMatrixMultiplication.
#
# Same shape and timing protocol as matmul_mlx.w / matmul_accelerate.w.
# Each K-iter call does the full encode + commit + waitUntilCompleted.

use core/mps
use core/blas

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

# metal_array (page-aligned) so MTLBuffer newBufferWithBytesNoCopy stays
# zero-copy. metal_array is from core/metal; pull it in.
# Actually core/blas's f32_array also uses w_array_new_aligned with -32,
# so it's already page-aligned.
a = f32_array(size)
b = f32_array(size)
c = f32_array(size)

i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

# Warm up — amortize MPS init, kernel JIT, MTLBuffer wrap caching.
mps_sgemm(a, b, c, n, n, n)
mps_sgemm(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  mps_sgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mps\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
