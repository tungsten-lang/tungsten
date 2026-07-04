# core/metal_sgemm_bf16 — reusable bf16-accumulator Metal matmul.
#
# Inputs are f32 (caller's convenience); we internally convert to bf16
# via a one-shot GPU kernel, then run a v3-shaped tiled matmul using
# simdgroup_bfloat8x8 inputs with fp32 accumulators. Output is f32.
#
# This is the "same precision as cuBLAS tf32 default" path — bf16
# multiplies, fp32 accumulate. Drop-in replacement for metal_sgemm
# whose performance edge over plain fp32 comes from the M-series tensor
# accelerators reaching higher throughput on bf16 inputs.
#
# Pipeline state (device, queue, conv pipeline, matmul pipeline,
# scratch bf16 buffers) is built once at module-load. Subsequent
# metal_sgemm_bf16 calls only run the dispatches.
#
# Constraint: square N divisible by 32, M=N=K.

use core/metal
use core/blas

# -- f32 → bf16 conversion kernel --
-> build_bf16_conv_msl
  s = StringBuffer(512)
  s << "#include <metal_stdlib>\n"
  s << "using namespace metal;\n"
  s << "kernel void f32_to_bf16(\n"
  s << "    device const float* src \[\[ buffer(0) \]\],\n"
  s << "    device bfloat* dst \[\[ buffer(1) \]\],\n"
  s << "    uint gid \[\[ thread_position_in_grid \]\]\n"
  s << ") {\n"
  s << "    dst\[gid\] = bfloat(src\[gid\]);\n"
  s << "}\n"
  s.to_s()

# -- bf16-input, fp32-acc tiled matmul kernel (v3 shape) --
-> build_bf16_matmul_msl
  s = StringBuffer(4096)
  s << "#include <metal_stdlib>\n"
  s << "#include <metal_simdgroup_matrix>\n"
  s << "using namespace metal;\n"
  s << "kernel void matmul_bf16(\n"
  s << "    device const bfloat* a \[\[ buffer(0) \]\],\n"
  s << "    device const bfloat* b \[\[ buffer(1) \]\],\n"
  s << "    device float* c \[\[ buffer(2) \]\],\n"
  s << "    constant int& n \[\[ buffer(3) \]\],\n"
  s << "    uint2 tgid \[\[ threadgroup_position_in_grid \]\]\n"
  s << ") {\n"
  s << "    int row = int(tgid.y) * 32;\n"
  s << "    int col = int(tgid.x) * 32;\n"
  s << "    simdgroup_float8x8 c00 = simdgroup_float8x8(0.0), c01 = simdgroup_float8x8(0.0), c02 = simdgroup_float8x8(0.0), c03 = simdgroup_float8x8(0.0);\n"
  s << "    simdgroup_float8x8 c10 = simdgroup_float8x8(0.0), c11 = simdgroup_float8x8(0.0), c12 = simdgroup_float8x8(0.0), c13 = simdgroup_float8x8(0.0);\n"
  s << "    simdgroup_float8x8 c20 = simdgroup_float8x8(0.0), c21 = simdgroup_float8x8(0.0), c22 = simdgroup_float8x8(0.0), c23 = simdgroup_float8x8(0.0);\n"
  s << "    simdgroup_float8x8 c30 = simdgroup_float8x8(0.0), c31 = simdgroup_float8x8(0.0), c32 = simdgroup_float8x8(0.0), c33 = simdgroup_float8x8(0.0);\n"
  s << "    simdgroup_bfloat8x8 a0, a1, a2, a3;\n"
  s << "    simdgroup_bfloat8x8 b0, b1, b2, b3;\n"
  s << "    for (int k = 0; k < n; k += 8) {\n"
  s << "        simdgroup_load(a0, a + (row +  0) * n + k, n);\n"
  s << "        simdgroup_load(a1, a + (row +  8) * n + k, n);\n"
  s << "        simdgroup_load(a2, a + (row + 16) * n + k, n);\n"
  s << "        simdgroup_load(a3, a + (row + 24) * n + k, n);\n"
  s << "        simdgroup_load(b0, b + k * n + (col +  0), n);\n"
  s << "        simdgroup_load(b1, b + k * n + (col +  8), n);\n"
  s << "        simdgroup_load(b2, b + k * n + (col + 16), n);\n"
  s << "        simdgroup_load(b3, b + k * n + (col + 24), n);\n"
  s << "        simdgroup_multiply_accumulate(c00, a0, b0, c00); simdgroup_multiply_accumulate(c01, a0, b1, c01); simdgroup_multiply_accumulate(c02, a0, b2, c02); simdgroup_multiply_accumulate(c03, a0, b3, c03);\n"
  s << "        simdgroup_multiply_accumulate(c10, a1, b0, c10); simdgroup_multiply_accumulate(c11, a1, b1, c11); simdgroup_multiply_accumulate(c12, a1, b2, c12); simdgroup_multiply_accumulate(c13, a1, b3, c13);\n"
  s << "        simdgroup_multiply_accumulate(c20, a2, b0, c20); simdgroup_multiply_accumulate(c21, a2, b1, c21); simdgroup_multiply_accumulate(c22, a2, b2, c22); simdgroup_multiply_accumulate(c23, a2, b3, c23);\n"
  s << "        simdgroup_multiply_accumulate(c30, a3, b0, c30); simdgroup_multiply_accumulate(c31, a3, b1, c31); simdgroup_multiply_accumulate(c32, a3, b2, c32); simdgroup_multiply_accumulate(c33, a3, b3, c33);\n"
  s << "    }\n"
  s << "    simdgroup_store(c00, c + (row +  0) * n + (col +  0), n); simdgroup_store(c01, c + (row +  0) * n + (col +  8), n); simdgroup_store(c02, c + (row +  0) * n + (col + 16), n); simdgroup_store(c03, c + (row +  0) * n + (col + 24), n);\n"
  s << "    simdgroup_store(c10, c + (row +  8) * n + (col +  0), n); simdgroup_store(c11, c + (row +  8) * n + (col +  8), n); simdgroup_store(c12, c + (row +  8) * n + (col + 16), n); simdgroup_store(c13, c + (row +  8) * n + (col + 24), n);\n"
  s << "    simdgroup_store(c20, c + (row + 16) * n + (col +  0), n); simdgroup_store(c21, c + (row + 16) * n + (col +  8), n); simdgroup_store(c22, c + (row + 16) * n + (col + 16), n); simdgroup_store(c23, c + (row + 16) * n + (col + 24), n);\n"
  s << "    simdgroup_store(c30, c + (row + 24) * n + (col +  0), n); simdgroup_store(c31, c + (row + 24) * n + (col +  8), n); simdgroup_store(c32, c + (row + 24) * n + (col + 16), n); simdgroup_store(c33, c + (row + 24) * n + (col + 24), n);\n"
  s << "}\n"
  s.to_s()

-> build_metal_sgemm_bf16_state
  device = metal_device()
  queue = metal_queue(device)
  conv_lib = metal_compile_source(device, build_bf16_conv_msl())
  conv_pipe = metal_pipeline(conv_lib, "f32_to_bf16")
  mm_lib = metal_compile_source(device, build_bf16_matmul_msl())
  mm_pipe = metal_pipeline(mm_lib, "matmul_bf16")
  {:device => device, :queue => queue, :conv => conv_pipe, :mm => mm_pipe}

METAL_SGEMM_BF16_STATE = build_metal_sgemm_bf16_state()

# C = A · B at bf16 internal precision (fp32 accumulator).
# A is M×K, B is K×N, C is M×N (all square: M=N=K=n).
# Inputs: f32 page-aligned arrays. Output: f32.
fn metal_sgemm_bf16(a, b, c, m, n, k)
  s = METAL_SGEMM_BF16_STATE
  device = s[:device]
  queue = s[:queue]
  size = n * n

  # Wrap f32 input arrays as MTLBuffers (zero-copy).
  a_buf = metal_buffer_for(device, a)
  b_buf = metal_buffer_for(device, b)
  c_buf = metal_buffer_for(device, c)

  # Allocate bf16 scratch arrays. Tungsten array allocation is page-
  # aligned via metal_array; metal_buffer_for then zero-copy-wraps it.
  a_bf16 = metal_array(-116, size)
  b_bf16 = metal_array(-116, size)
  a_bf16_buf = metal_buffer_for(device, a_bf16)
  b_bf16_buf = metal_buffer_for(device, b_bf16)

  # f32 → bf16 conversion (two dispatches; cheap relative to matmul).
  metal_dispatch_n(queue, s[:conv], [a_buf, a_bf16_buf], size)
  metal_dispatch_n(queue, s[:conv], [b_buf, b_bf16_buf], size)

  # n constant buffer
  n_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(n_buf, 0, n)

  # Matmul dispatch — N/32 × N/32 threadgroups, 32 threads each.
  n_tg = n / 32
  metal_dispatch_3d(queue, s[:mm], [a_bf16_buf, b_bf16_buf, c_buf, n_buf], n_tg, n_tg, 1, 32, 1, 1)
