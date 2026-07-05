# Tungsten-native @gpu fn matmul — bf16 inputs, fp32 accumulator.
#
# Tests the emitter's `simdgroup_bfloat8x8` (sg_bf16) support.
# Algorithm is identical to matmul_metal_gpufn.w (32×32 per SIMD-group)
# but every A/B simdgroup matrix is bf16 instead of fp32. The mixed-
# precision `simdgroup_multiply_accumulate(c_f32, a_bf16, b_bf16, c_f32)`
# form uses the M-series matrix accelerator at potentially higher
# throughput than the all-fp32 path.

use core/metal
use core/blas
use core/mlx    # for f32_to_bf16 helper

## bf16[]: a
## bf16[]: b
## f32[]: c
## i32: n
@gpu fn matmul_tiled_bf16(a, b, c, n)
  row = gpu.threadgroup_position_in_grid.y * 32 ## i32
  col = gpu.threadgroup_position_in_grid.x * 32 ## i32

  c00 = simdgroup_float8x8(~0.0) ## sg_f32
  c01 = simdgroup_float8x8(~0.0) ## sg_f32
  c02 = simdgroup_float8x8(~0.0) ## sg_f32
  c03 = simdgroup_float8x8(~0.0) ## sg_f32
  c10 = simdgroup_float8x8(~0.0) ## sg_f32
  c11 = simdgroup_float8x8(~0.0) ## sg_f32
  c12 = simdgroup_float8x8(~0.0) ## sg_f32
  c13 = simdgroup_float8x8(~0.0) ## sg_f32
  c20 = simdgroup_float8x8(~0.0) ## sg_f32
  c21 = simdgroup_float8x8(~0.0) ## sg_f32
  c22 = simdgroup_float8x8(~0.0) ## sg_f32
  c23 = simdgroup_float8x8(~0.0) ## sg_f32
  c30 = simdgroup_float8x8(~0.0) ## sg_f32
  c31 = simdgroup_float8x8(~0.0) ## sg_f32
  c32 = simdgroup_float8x8(~0.0) ## sg_f32
  c33 = simdgroup_float8x8(~0.0) ## sg_f32

  # Default-init (no scalar broadcast for bfloat simdgroup) — gets
  # overwritten by the simdgroup_load below before use.
  a0 = simdgroup_bfloat8x8() ## sg_bf16
  a1 = simdgroup_bfloat8x8() ## sg_bf16
  a2 = simdgroup_bfloat8x8() ## sg_bf16
  a3 = simdgroup_bfloat8x8() ## sg_bf16
  b0 = simdgroup_bfloat8x8() ## sg_bf16
  b1 = simdgroup_bfloat8x8() ## sg_bf16
  b2 = simdgroup_bfloat8x8() ## sg_bf16
  b3 = simdgroup_bfloat8x8() ## sg_bf16

  k = 0 ## i32
  while k < n
    simdgroup_load(a0, a, (row + 0) * n + k, n)
    simdgroup_load(a1, a, (row + 8) * n + k, n)
    simdgroup_load(a2, a, (row + 16) * n + k, n)
    simdgroup_load(a3, a, (row + 24) * n + k, n)
    simdgroup_load(b0, b, k * n + (col + 0), n)
    simdgroup_load(b1, b, k * n + (col + 8), n)
    simdgroup_load(b2, b, k * n + (col + 16), n)
    simdgroup_load(b3, b, k * n + (col + 24), n)
    simdgroup_multiply_accumulate(c00, a0, b0, c00)
    simdgroup_multiply_accumulate(c01, a0, b1, c01)
    simdgroup_multiply_accumulate(c02, a0, b2, c02)
    simdgroup_multiply_accumulate(c03, a0, b3, c03)
    simdgroup_multiply_accumulate(c10, a1, b0, c10)
    simdgroup_multiply_accumulate(c11, a1, b1, c11)
    simdgroup_multiply_accumulate(c12, a1, b2, c12)
    simdgroup_multiply_accumulate(c13, a1, b3, c13)
    simdgroup_multiply_accumulate(c20, a2, b0, c20)
    simdgroup_multiply_accumulate(c21, a2, b1, c21)
    simdgroup_multiply_accumulate(c22, a2, b2, c22)
    simdgroup_multiply_accumulate(c23, a2, b3, c23)
    simdgroup_multiply_accumulate(c30, a3, b0, c30)
    simdgroup_multiply_accumulate(c31, a3, b1, c31)
    simdgroup_multiply_accumulate(c32, a3, b2, c32)
    simdgroup_multiply_accumulate(c33, a3, b3, c33)
    k = k + 8

  simdgroup_store(c00, c, (row + 0) * n + (col + 0), n)
  simdgroup_store(c01, c, (row + 0) * n + (col + 8), n)
  simdgroup_store(c02, c, (row + 0) * n + (col + 16), n)
  simdgroup_store(c03, c, (row + 0) * n + (col + 24), n)
  simdgroup_store(c10, c, (row + 8) * n + (col + 0), n)
  simdgroup_store(c11, c, (row + 8) * n + (col + 8), n)
  simdgroup_store(c12, c, (row + 8) * n + (col + 16), n)
  simdgroup_store(c13, c, (row + 8) * n + (col + 24), n)
  simdgroup_store(c20, c, (row + 16) * n + (col + 0), n)
  simdgroup_store(c21, c, (row + 16) * n + (col + 8), n)
  simdgroup_store(c22, c, (row + 16) * n + (col + 16), n)
  simdgroup_store(c23, c, (row + 16) * n + (col + 24), n)
  simdgroup_store(c30, c, (row + 24) * n + (col + 0), n)
  simdgroup_store(c31, c, (row + 24) * n + (col + 8), n)
  simdgroup_store(c32, c, (row + 24) * n + (col + 16), n)
  simdgroup_store(c33, c, (row + 24) * n + (col + 24), n)

# ---- Driver ----

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

msl_path = "/tmp/tungsten/matmul_metal_gpufn_bf16.metal"
msl = read_file(msl_path)

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "matmul_tiled_bf16")

# f32 fill on CPU, then GPU-convert to bf16 (same path as matmul_metal_bf16.w)
a_f32 = f32_array(size)
b_f32 = f32_array(size)
a_bf16 = metal_array(-116, size)
b_bf16 = metal_array(-116, size)
c_f32 = metal_array(-32, size)

i = 0
while i < size
  a_f32[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b_f32[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

f32_to_bf16(a_f32, a_bf16, size)
f32_to_bf16(b_f32, b_bf16, size)

a_buf = metal_buffer_for(device, a_bf16)
b_buf = metal_buffer_for(device, b_bf16)
c_buf = metal_buffer_for(device, c_f32)
n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, n)

queue = metal_queue(device)
n_tg = n / 32
bufs = [a_buf, b_buf, c_buf, n_buf]

metal_dispatch_3d(queue, pipeline, bufs, n_tg, n_tg, 1, 32, 1, 1)
metal_dispatch_3d(queue, pipeline, bufs, n_tg, n_tg, 1, 32, 1, 1)

t0 = clock()
iter = 0
while iter < k_iters
  metal_dispatch_3d(queue, pipeline, bufs, n_tg, n_tg, 1, 32, 1, 1)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-gpufn-bf16\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
