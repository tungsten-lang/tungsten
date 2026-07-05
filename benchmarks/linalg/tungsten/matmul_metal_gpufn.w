# Tungsten-native @gpu fn matmul, using the metal_emitter's new
# simdgroup_matrix support.
#
# Same algorithm as our hand-rolled v3 (32×32 per SG, 16 accumulators)
# but written as a Tungsten @gpu fn — the compiler lowers it to MSL.
# This validates the emitter extension end-to-end.

use core/metal
use core/blas

## f32[]: a
## f32[]: b
## f32[]: c
## i32: n
@gpu fn matmul_tiled(a, b, c, n)
  row = gpu.threadgroup_position_in_grid.y * 32 ## i32
  col = gpu.threadgroup_position_in_grid.x * 32 ## i32

  # 16 accumulators arranged as a 4×4 grid of 8×8 tiles.
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

  a0 = simdgroup_float8x8(~0.0) ## sg_f32
  a1 = simdgroup_float8x8(~0.0) ## sg_f32
  a2 = simdgroup_float8x8(~0.0) ## sg_f32
  a3 = simdgroup_float8x8(~0.0) ## sg_f32
  b0 = simdgroup_float8x8(~0.0) ## sg_f32
  b1 = simdgroup_float8x8(~0.0) ## sg_f32
  b2 = simdgroup_float8x8(~0.0) ## sg_f32
  b3 = simdgroup_float8x8(~0.0) ## sg_f32

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

# ---- Driver: load the emitted .metal sidecar, dispatch, time ----

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

# The compiler writes <basename>.metal next to the .ll. When we built
# with -o /path/to/foo, the .ll lives at /path/to/foo.ll and the
# sidecar at /path/to/foo.metal. Read it back here.
msl_path = ARGV[2]
if msl_path == nil
  msl_path = "benchmarks/linalg/tungsten/matmul_metal_gpufn.metal"

msl = read_file(msl_path)

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "matmul_tiled")

a = metal_array(-32, size)
b = metal_array(-32, size)
c = metal_array(-32, size)

i = 0
while i < size
  a[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

a_buf = metal_buffer_for(device, a)
b_buf = metal_buffer_for(device, b)
c_buf = metal_buffer_for(device, c)

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

<< "{\"impl\":\"tungsten-gpufn\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
