# Demo: sgemm_auto picks the right backend by size.
#
# Runs the same sgemm across N=128..8192 via core/sgemm_auto and
# reports GFLOPS. Should match accelerate's numbers for small N and
# MLX's numbers for large N.
#
# Build with the MLX bridge spliced in (sgemm_auto links it):
#   benchmarks/linalg/tungsten/build_auto_bench.sh

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

sgemm_auto(a, b, c, n, n, n)
sgemm_auto(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  sgemm_auto(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

# sgemm_auto's dispatch target is baked in at compile time (--fast-math
# flag). The display label can't query this at runtime, so we just show
# the strict-mode pick. Use the GFLOPS number to tell which actually ran:
# strict tops out around 12 TFLOPS, fast (mlx) hits ~28 TFLOPS at N=8192.
if n < 1024
  picked = "accelerate"
else
  picked = "metal-tiled-or-mlx"

<< "{\"impl\":\"tungsten-auto\",\"picked\":\""
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
