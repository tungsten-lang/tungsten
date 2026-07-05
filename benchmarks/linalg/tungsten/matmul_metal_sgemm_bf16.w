# Smoke + perf for core/metal_sgemm_bf16.
# Conversion overhead is included in each timed iteration (real workload cost).

use core/metal_sgemm_bf16
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

metal_sgemm_bf16(a, b, c, n, n, n)
metal_sgemm_bf16(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  metal_sgemm_bf16(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-metal-sgemm-bf16\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
