# Tungsten matmul benchmark — dispatches to Apple MLX via the
# core/mlx bridge (runtime/mlx_bridge.c + mlx-c). This is the
# pure-GPU comparison row: how fast can the M-series GPU push f32
# matmul through MLX's Metal kernels, with no nanboxing and no
# CPU→GPU copies (unified memory).
#
# Shape conventions and JSON output match matmul_accelerate.w so
# results.md can paste them side by side.

use core/mlx
use core/blas    # for f32_array — same typed-array allocator

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

a = f32_array(size)
b = f32_array(size)
c = f32_array(size)

# Deterministic fill — matches the C / Rust / Python / Swift / Tungsten-accel harnesses.
i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

# Warm up — amortize MLX init, stream setup, kernel JIT.
mlx_sgemm(a, b, c, n, n, n)
mlx_sgemm(a, b, c, n, n, n)

# Timed loop — K matmuls inside one clock region. Each call performs
# the full readback (so apples-to-apples vs cblas_sgemm).
t0 = clock()
iter = 0
while iter < k_iters
  mlx_sgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mlx\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
