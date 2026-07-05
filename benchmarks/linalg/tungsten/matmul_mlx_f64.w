# MLX f64 matmul benchmark. Same shape as matmul_mlx.w but f64 throughout.
# Apple Silicon Metal GPU has no native f64 matmul, so MLX likely runs
# this on the CPU stream — useful baseline for accelerate dgemm comparison.

use core/mlx
use core/blas

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = f64_array(size)
b = f64_array(size)
c = f64_array(size)

i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

mlx_dgemm(a, b, c, n, n, n)
mlx_dgemm(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  mlx_dgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mlx-f64\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
