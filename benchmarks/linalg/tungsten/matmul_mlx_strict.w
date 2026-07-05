# Same as matmul_mlx.w but sets MLX_ENABLE_TF32=0 before first call.
use core/mlx
use core/blas

# Set strict f32 mode in MLX — must happen before first mlx_matmul.
# Routed through w_setenv (not libc setenv directly): ccall passes boxed
# WValue strings, which raw setenv would deref as a char* and crash. w_setenv
# unboxes them C-side first.
ccall("w_setenv", "MLX_ENABLE_TF32", "0")

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

mlx_sgemm(a, b, c, n, n, n)
mlx_sgemm(a, b, c, n, n, n)

t0 = clock()
iter = 0
while iter < k_iters
  mlx_sgemm(a, b, c, n, n, n)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-mlx-strict\",\"N\":" << n << ",\"K\":" << k_iters << ",\"median_ms\":" << median_ms << ",\"gflops\":" << gflops << "}"
