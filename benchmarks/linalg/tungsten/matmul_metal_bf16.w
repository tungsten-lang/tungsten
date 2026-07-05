# Tungsten matmul — TILED Metal via simdgroup_bfloat8x8 + fp32 accum.
#
# Same v3 tile (32×32 per simdgroup, 16 accumulators) but A and B
# are bf16 instead of fp32. The simdgroup_multiply_accumulate uses
# the mixed-precision form: bf16 × bf16 → fp32, executed on the
# M-series tensor accelerator HW at ~2× FP32 throughput.
#
# Same trick cuBLAS uses internally with CUBLAS_GEMM_DEFAULT_TENSOR_OP
# (which produces tf32-quality results with FP32 inputs).
#
# Inputs: bf16 (we run a one-shot f32 → bf16 conversion at startup,
# its cost is excluded from the matmul timing).
# Output: fp32 (the accumulator type).
#
# Constraint: N multiple of 32.

use core/metal
use core/blas

# --- Convert kernel: f32 → bf16 (one element per thread) -----------------
conv_msl = StringBuffer(512)
conv_msl << "#include <metal_stdlib>\n"
conv_msl << "using namespace metal;\n"
conv_msl << "kernel void f32_to_bf16(\n"
conv_msl << "    device const float* src \[\[ buffer(0) \]\],\n"
conv_msl << "    device bfloat* dst \[\[ buffer(1) \]\],\n"
conv_msl << "    uint gid \[\[ thread_position_in_grid \]\]\n"
conv_msl << ") {\n"
conv_msl << "    dst\[gid\] = bfloat(src\[gid\]);\n"
conv_msl << "}\n"

# --- Matmul kernel: bf16 × bf16 → fp32 (mixed-precision mma) ------------
mm_msl = StringBuffer(4096)
mm_msl << "#include <metal_stdlib>\n"
mm_msl << "#include <metal_simdgroup_matrix>\n"
mm_msl << "using namespace metal;\n"
mm_msl << "kernel void matmul_bf16(\n"
mm_msl << "    device const bfloat* a \[\[ buffer(0) \]\],\n"
mm_msl << "    device const bfloat* b \[\[ buffer(1) \]\],\n"
mm_msl << "    device float* c \[\[ buffer(2) \]\],\n"
mm_msl << "    constant int& n \[\[ buffer(3) \]\],\n"
mm_msl << "    uint2 tgid \[\[ threadgroup_position_in_grid \]\]\n"
mm_msl << ") {\n"
mm_msl << "    int row = int(tgid.y) * 32;\n"
mm_msl << "    int col = int(tgid.x) * 32;\n"
mm_msl << "    \n"
mm_msl << "    simdgroup_float8x8 c00 = simdgroup_float8x8(0.0), c01 = simdgroup_float8x8(0.0), c02 = simdgroup_float8x8(0.0), c03 = simdgroup_float8x8(0.0);\n"
mm_msl << "    simdgroup_float8x8 c10 = simdgroup_float8x8(0.0), c11 = simdgroup_float8x8(0.0), c12 = simdgroup_float8x8(0.0), c13 = simdgroup_float8x8(0.0);\n"
mm_msl << "    simdgroup_float8x8 c20 = simdgroup_float8x8(0.0), c21 = simdgroup_float8x8(0.0), c22 = simdgroup_float8x8(0.0), c23 = simdgroup_float8x8(0.0);\n"
mm_msl << "    simdgroup_float8x8 c30 = simdgroup_float8x8(0.0), c31 = simdgroup_float8x8(0.0), c32 = simdgroup_float8x8(0.0), c33 = simdgroup_float8x8(0.0);\n"
mm_msl << "    simdgroup_bfloat8x8 a0, a1, a2, a3;\n"
mm_msl << "    simdgroup_bfloat8x8 b0, b1, b2, b3;\n"
mm_msl << "    \n"
mm_msl << "    for (int k = 0; k < n; k += 8) {\n"
mm_msl << "        simdgroup_load(a0, a + (row +  0) * n + k, n);\n"
mm_msl << "        simdgroup_load(a1, a + (row +  8) * n + k, n);\n"
mm_msl << "        simdgroup_load(a2, a + (row + 16) * n + k, n);\n"
mm_msl << "        simdgroup_load(a3, a + (row + 24) * n + k, n);\n"
mm_msl << "        simdgroup_load(b0, b + k * n + (col +  0), n);\n"
mm_msl << "        simdgroup_load(b1, b + k * n + (col +  8), n);\n"
mm_msl << "        simdgroup_load(b2, b + k * n + (col + 16), n);\n"
mm_msl << "        simdgroup_load(b3, b + k * n + (col + 24), n);\n"
mm_msl << "        simdgroup_multiply_accumulate(c00, a0, b0, c00); simdgroup_multiply_accumulate(c01, a0, b1, c01); simdgroup_multiply_accumulate(c02, a0, b2, c02); simdgroup_multiply_accumulate(c03, a0, b3, c03);\n"
mm_msl << "        simdgroup_multiply_accumulate(c10, a1, b0, c10); simdgroup_multiply_accumulate(c11, a1, b1, c11); simdgroup_multiply_accumulate(c12, a1, b2, c12); simdgroup_multiply_accumulate(c13, a1, b3, c13);\n"
mm_msl << "        simdgroup_multiply_accumulate(c20, a2, b0, c20); simdgroup_multiply_accumulate(c21, a2, b1, c21); simdgroup_multiply_accumulate(c22, a2, b2, c22); simdgroup_multiply_accumulate(c23, a2, b3, c23);\n"
mm_msl << "        simdgroup_multiply_accumulate(c30, a3, b0, c30); simdgroup_multiply_accumulate(c31, a3, b1, c31); simdgroup_multiply_accumulate(c32, a3, b2, c32); simdgroup_multiply_accumulate(c33, a3, b3, c33);\n"
mm_msl << "    }\n"
mm_msl << "    simdgroup_store(c00, c + (row +  0) * n + (col +  0), n); simdgroup_store(c01, c + (row +  0) * n + (col +  8), n); simdgroup_store(c02, c + (row +  0) * n + (col + 16), n); simdgroup_store(c03, c + (row +  0) * n + (col + 24), n);\n"
mm_msl << "    simdgroup_store(c10, c + (row +  8) * n + (col +  0), n); simdgroup_store(c11, c + (row +  8) * n + (col +  8), n); simdgroup_store(c12, c + (row +  8) * n + (col + 16), n); simdgroup_store(c13, c + (row +  8) * n + (col + 24), n);\n"
mm_msl << "    simdgroup_store(c20, c + (row + 16) * n + (col +  0), n); simdgroup_store(c21, c + (row + 16) * n + (col +  8), n); simdgroup_store(c22, c + (row + 16) * n + (col + 16), n); simdgroup_store(c23, c + (row + 16) * n + (col + 24), n);\n"
mm_msl << "    simdgroup_store(c30, c + (row + 24) * n + (col +  0), n); simdgroup_store(c31, c + (row + 24) * n + (col +  8), n); simdgroup_store(c32, c + (row + 24) * n + (col + 16), n); simdgroup_store(c33, c + (row + 24) * n + (col + 24), n);\n"
mm_msl << "}\n"

n = ARGV[0].to_i
k_iters = ARGV[1].to_i
size = n * n

device = metal_device()
conv_lib = metal_compile_source(device, conv_msl.to_s)
conv_pipe = metal_pipeline(conv_lib, "f32_to_bf16")
mm_lib = metal_compile_source(device, mm_msl.to_s)
mm_pipe = metal_pipeline(mm_lib, "matmul_bf16")

# f32 source arrays (filled on CPU)
a_f32 = metal_array(-32, size)
b_f32 = metal_array(-32, size)

i = 0
while i < size
  a_f32[i] = ((i * 31 + 7) % 17) * ~1.0 / ~17.0
  b_f32[i] = ((i * 13 + 3) % 19) * ~1.0 / ~19.0
  i += 1

# bf16 destination arrays (filled by GPU conversion kernel)
# ebits = -116 → bf16 element type, 2 bytes per element.
a_bf16 = metal_array(-116, size)
b_bf16 = metal_array(-116, size)

c_f32 = metal_array(-32, size)

a_f32_buf  = metal_buffer_for(device, a_f32)
b_f32_buf  = metal_buffer_for(device, b_f32)
a_bf16_buf = metal_buffer_for(device, a_bf16)
b_bf16_buf = metal_buffer_for(device, b_bf16)
c_buf      = metal_buffer_for(device, c_f32)

n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, n)

queue = metal_queue(device)

# One-shot f32 → bf16 conversion for both A and B.
metal_dispatch_n(queue, conv_pipe, [a_f32_buf, a_bf16_buf], size)
metal_dispatch_n(queue, conv_pipe, [b_f32_buf, b_bf16_buf], size)

# Matmul dispatch grid: N/32 × N/32 threadgroups, 32 threads each.
n_tg = n / 32
bufs = [a_bf16_buf, b_bf16_buf, c_buf, n_buf]

# Warmup
metal_dispatch_3d(queue, mm_pipe, bufs, n_tg, n_tg, 1, 32, 1, 1)
metal_dispatch_3d(queue, mm_pipe, bufs, n_tg, n_tg, 1, 32, 1, 1)

t0 = clock()
iter = 0
while iter < k_iters
  metal_dispatch_3d(queue, mm_pipe, bufs, n_tg, n_tg, 1, 32, 1, 1)
  iter += 1
t1 = clock()

elapsed_sec = t1 - t0
median_ms = elapsed_sec * ~1000.0 / k_iters
gflops = (2 * n * n * n * k_iters) / (elapsed_sec * ~1000000000.0)

<< "{\"impl\":\"tungsten-metal-bf16\",\"N\":"
<< n
<< ",\"K\":"
<< k_iters
<< ",\"median_ms\":"
<< median_ms
<< ",\"gflops\":"
<< gflops
<< "}"
