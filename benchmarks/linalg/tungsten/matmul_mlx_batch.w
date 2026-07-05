# Tungsten matmul benchmark — MLX with a single eval barrier across K iters.
#
# Measures MLX's PEAK throughput: schedules K matmuls into the graph,
# then forces a single mlx_array_eval() at the end. No per-call sync,
# no readback. The difference vs matmul_mlx.w tells us how much of
# the 7000 GFLOPS at N=2048 was per-call overhead vs actual GPU
# throughput ceiling.
#
# Shape conventions and JSON output match matmul_mlx.w.

use core/mlx
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

# Warm up — single-call eval to amortize MLX init.
mlx_sgemm(a, b, c, n, n, n)
mlx_sgemm(a, b, c, n, n, n)

# The whole K-iter loop happens inside the bridge: schedule K matmuls,
# single eval at the end.
t0 = clock()
mlx_sgemm_batch(a, b, c, n, n, n, k_iters)
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mlx-batch\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
