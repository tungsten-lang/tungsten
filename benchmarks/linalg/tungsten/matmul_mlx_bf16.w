# MLX bf16 matmul benchmark. f32 fill on CPU → bf16 conversion → bf16 matmul.
# bf16 inputs let MLX engage the M5 Max tensor accelerators at higher
# effective throughput than fp32.

use core/mlx
use core/blas
use core/metal    # for metal_array (ebits=-116 → bf16)

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

# Fill on CPU as f32 (deterministic, matches the other benches)
a_f32 = f32_array(size)
b_f32 = f32_array(size)
i = 0
while i < size
  a_f32[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b_f32[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

# bf16 inputs + bf16 accumulator output
a = metal_array(-116, size)
b = metal_array(-116, size)
c = metal_array(-116, size)

# CPU-side f32 → bf16 conversion (cost not in the matmul timing)
f32_to_bf16(a_f32, a, size)
f32_to_bf16(b_f32, b, size)

mlx_bgemm(a, b, c, n, n, n)
mlx_bgemm(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  mlx_bgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mlx-bf16\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
