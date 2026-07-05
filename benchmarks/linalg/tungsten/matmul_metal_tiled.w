# Tungsten matmul — TILED Metal dispatch via simdgroup_matrix.
#
# Best of several tile sizes tried (v3 won):
#   v1 (8×8  per SG, 1 acc):  5.1 → 4.5 → 3.1 TFLOPS @ N=2k/4k/8k
#   v2 (16×16 per SG, 4 acc): 6.1 → 10.6 → 7.5 TFLOPS
#   v3 (32×32 per SG, 16 acc): 5.7 → 14.3 → 13.7 TFLOPS  ← winner
#   v4 (TG-shared, 4 SGs, 64×64 per TG): 6.1 → 13.1 → 11.6 TFLOPS
#
# v4 underperformed v3 because Metal's simdgroup_load from device
# memory is already coalesced/cached well, and the TG-barrier + tg-
# cooperative-load overhead ate the bandwidth savings from sharing
# A loads across 2 SGs.
#
# Algorithm per threadgroup (= 1 SIMD-group = 32 threads):
#   - 16 accumulators c[0..4, 0..4] (each simdgroup_float8x8) → 32×32 output
#   - Outer K-loop step 8:
#       load A[row..row+32, k..k+8] as 4 SG matrices a0..a3
#       load B[k..k+8, col..col+32] as 4 SG matrices b0..b3
#       16 mma: c[i,j] += a[i] * b[j]
#   - Result: 8 device loads → 16 mma per K step (8192 FMAs / 512 floats
#     loaded = 16 FMAs per loaded float)
#
# Constraint: N multiple of 32.

use core/metal
use core/blas

msl_src = StringBuffer(4096)
msl_src << "#include <metal_stdlib>\n"
msl_src << "#include <metal_simdgroup_matrix>\n"
msl_src << "using namespace metal;\n"
msl_src << "kernel void matmul_tiled(\n"
msl_src << "    device const float* a \[\[ buffer(0) \]\],\n"
msl_src << "    device const float* b \[\[ buffer(1) \]\],\n"
msl_src << "    device float* c \[\[ buffer(2) \]\],\n"
msl_src << "    constant int& n \[\[ buffer(3) \]\],\n"
msl_src << "    uint2 tgid \[\[ threadgroup_position_in_grid \]\]\n"
msl_src << ") {\n"
msl_src << "    int row = int(tgid.y) * 32;\n"
msl_src << "    int col = int(tgid.x) * 32;\n"
msl_src << "    \n"
msl_src << "    simdgroup_float8x8 c00 = simdgroup_float8x8(0.0), c01 = simdgroup_float8x8(0.0), c02 = simdgroup_float8x8(0.0), c03 = simdgroup_float8x8(0.0);\n"
msl_src << "    simdgroup_float8x8 c10 = simdgroup_float8x8(0.0), c11 = simdgroup_float8x8(0.0), c12 = simdgroup_float8x8(0.0), c13 = simdgroup_float8x8(0.0);\n"
msl_src << "    simdgroup_float8x8 c20 = simdgroup_float8x8(0.0), c21 = simdgroup_float8x8(0.0), c22 = simdgroup_float8x8(0.0), c23 = simdgroup_float8x8(0.0);\n"
msl_src << "    simdgroup_float8x8 c30 = simdgroup_float8x8(0.0), c31 = simdgroup_float8x8(0.0), c32 = simdgroup_float8x8(0.0), c33 = simdgroup_float8x8(0.0);\n"
msl_src << "    simdgroup_float8x8 a0, a1, a2, a3;\n"
msl_src << "    simdgroup_float8x8 b0, b1, b2, b3;\n"
msl_src << "    \n"
msl_src << "    for (int k = 0; k < n; k += 8) {\n"
msl_src << "        simdgroup_load(a0, a + (row +  0) * n + k, n);\n"
msl_src << "        simdgroup_load(a1, a + (row +  8) * n + k, n);\n"
msl_src << "        simdgroup_load(a2, a + (row + 16) * n + k, n);\n"
msl_src << "        simdgroup_load(a3, a + (row + 24) * n + k, n);\n"
msl_src << "        simdgroup_load(b0, b + k * n + (col +  0), n);\n"
msl_src << "        simdgroup_load(b1, b + k * n + (col +  8), n);\n"
msl_src << "        simdgroup_load(b2, b + k * n + (col + 16), n);\n"
msl_src << "        simdgroup_load(b3, b + k * n + (col + 24), n);\n"
msl_src << "        simdgroup_multiply_accumulate(c00, a0, b0, c00); simdgroup_multiply_accumulate(c01, a0, b1, c01); simdgroup_multiply_accumulate(c02, a0, b2, c02); simdgroup_multiply_accumulate(c03, a0, b3, c03);\n"
msl_src << "        simdgroup_multiply_accumulate(c10, a1, b0, c10); simdgroup_multiply_accumulate(c11, a1, b1, c11); simdgroup_multiply_accumulate(c12, a1, b2, c12); simdgroup_multiply_accumulate(c13, a1, b3, c13);\n"
msl_src << "        simdgroup_multiply_accumulate(c20, a2, b0, c20); simdgroup_multiply_accumulate(c21, a2, b1, c21); simdgroup_multiply_accumulate(c22, a2, b2, c22); simdgroup_multiply_accumulate(c23, a2, b3, c23);\n"
msl_src << "        simdgroup_multiply_accumulate(c30, a3, b0, c30); simdgroup_multiply_accumulate(c31, a3, b1, c31); simdgroup_multiply_accumulate(c32, a3, b2, c32); simdgroup_multiply_accumulate(c33, a3, b3, c33);\n"
msl_src << "    }\n"
msl_src << "    simdgroup_store(c00, c + (row +  0) * n + (col +  0), n); simdgroup_store(c01, c + (row +  0) * n + (col +  8), n); simdgroup_store(c02, c + (row +  0) * n + (col + 16), n); simdgroup_store(c03, c + (row +  0) * n + (col + 24), n);\n"
msl_src << "    simdgroup_store(c10, c + (row +  8) * n + (col +  0), n); simdgroup_store(c11, c + (row +  8) * n + (col +  8), n); simdgroup_store(c12, c + (row +  8) * n + (col + 16), n); simdgroup_store(c13, c + (row +  8) * n + (col + 24), n);\n"
msl_src << "    simdgroup_store(c20, c + (row + 16) * n + (col +  0), n); simdgroup_store(c21, c + (row + 16) * n + (col +  8), n); simdgroup_store(c22, c + (row + 16) * n + (col + 16), n); simdgroup_store(c23, c + (row + 16) * n + (col + 24), n);\n"
msl_src << "    simdgroup_store(c30, c + (row + 24) * n + (col +  0), n); simdgroup_store(c31, c + (row + 24) * n + (col +  8), n); simdgroup_store(c32, c + (row + 24) * n + (col + 16), n); simdgroup_store(c33, c + (row + 24) * n + (col + 24), n);\n"
msl_src << "}\n"

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

device = metal_device()
library = metal_compile_source(device, msl_src.to_s)
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

# Grid: N/32 × N/32 threadgroups, each 32×1×1 = 1 SIMD-group.
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

<< "{\"impl\":\"tungsten-metal-tiled\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
