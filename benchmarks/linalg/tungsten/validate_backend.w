# Generic correctness validator: compares each backend's f32 matmul
# output against Accelerate cblas_sgemm as the ground-truth reference.
#
# Args: backend_id N
#
# Prints JSON with max_abs_err (we skip max_rel to avoid Tungsten's
# float type-inference pitfalls). Tolerance is per-backend.

use core/sgemm_auto

backend_id = ARGV[0]
n = ARGV[1].to_i
size = n * n

a = f32_array(size)
b = f32_array(size)
c_ref = f32_array(size)
c_test = f32_array(size)

i = 0
while i < size
  a[i] = ((i * 7 + 13) % 17) * ~1.0 / ~3.7
  b[i] = ((i * 11 + 5) % 19) * ~1.0 / ~5.3
  i += 1

sgemm(a, b, c_ref, n, n, n)

if backend_id == "accelerate"
  sgemm(a, b, c_test, n, n, n)
elsif backend_id == "metal-tiled"
  metal_sgemm(a, b, c_test, n, n, n)
elsif backend_id == "metal-bf16"
  metal_sgemm_bf16(a, b, c_test, n, n, n)
elsif backend_id == "mlx"
  mlx_sgemm(a, b, c_test, n, n, n)
else
  << "{\"backend\":\"" + backend_id + "\",\"ok\":false}"
  exit 1

# Find max absolute error (simpler than relative; tolerance still
# differentiates bf16 vs f32 backends).
max_abs = ~0.0
i = 0
while i < size
  d = c_ref[i] - c_test[i]
  if d < ~0.0
    d = ~0.0 - d
  if d > max_abs
    max_abs = d
  i += 1

# Per-backend absolute tolerance scaled by expected output magnitude
# at this size. For our fill pattern, output values at N=128 are
# O(N) ≈ 100, so tolerances scale roughly with N.
tol = n * ~0.001    # f32 default: 0.1% absolute deviation per element
if backend_id == "metal-bf16"
  tol = n * ~0.1   # bf16 has ~3 digits — much wider tolerance

ok_str = "false"
if max_abs < tol
  ok_str = "true"

<< "{\"backend\":\""
<< backend_id
<< "\",\"N\":"
<< n.to_s
<< ",\"max_abs_err\":"
<< max_abs.to_s
<< ",\"tolerance\":"
<< tol.to_s
<< ",\"ok\":"
<< ok_str
<< "}"
