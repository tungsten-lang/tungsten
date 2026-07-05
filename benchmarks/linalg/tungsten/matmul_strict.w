# Demonstrates sgemm_strict — same shape as matmul_auto but routes
# only to true-f32 backends.

use core/sgemm_auto
use core/blas

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = f32_array(size)
b = f32_array(size)
c = f32_array(size)

i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

sgemm_strict(a, b, c, n, n, n)
sgemm_strict(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  sgemm_strict(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

picked = "accelerate"
if n >= 1024
  picked = "metal-tiled"

<< "{\"impl\":\"tungsten-strict\",\"picked\":\""
<< picked
<< "\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
