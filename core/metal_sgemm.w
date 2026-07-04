# core/metal_sgemm — reusable Tungsten-native Metal matmul.
#
# Wraps the v3 tiled simdgroup_matrix kernel into a callable
# `metal_sgemm(a, b, c, m, n, k)` function. Pipeline is compiled
# once at module-load time and cached for the process lifetime.
#
# Constraint: N must be a multiple of 32 and M=N=K (square). When
# either is violated, callers should fall through to mlx_sgemm.
#
# Used by sgemm_auto when the policy picks "metal-tiled" for the
# input size band.

use core/metal
use core/blas

# Assemble the MSL source. Tungsten string interpolation uses `[...]`,
# so the MSL `[[ buffer(N) ]]` attributes need backslash-escaped brackets.
-> build_metal_sgemm_msl
  s = StringBuffer(4096)
  s << "#include <metal_stdlib>\n"
  s << "#include <metal_simdgroup_matrix>\n"
  s << "using namespace metal;\n"
  s << "kernel void matmul_tiled(\n"
  s << "    device const float* a \[\[ buffer(0) \]\],\n"
  s << "    device const float* b \[\[ buffer(1) \]\],\n"
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
  s << "    simdgroup_float8x8 a0, a1, a2, a3, b0, b1, b2, b3;\n"
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

# Cached pipeline state — built once at module-load.
-> build_metal_sgemm_state
  device = metal_device()
  queue = metal_queue(device)
  library = metal_compile_source(device, build_metal_sgemm_msl())
  pipeline = metal_pipeline(library, "matmul_tiled")
  {:device => device, :queue => queue, :pipeline => pipeline}

METAL_SGEMM_STATE = build_metal_sgemm_state()

# C = A · B via hand-tuned Metal v3 (simdgroup_float8x8, 32×32 tiles).
# Inputs/outputs must be page-aligned f32 arrays (use core/metal::metal_array(-32,N)
# or core/blas::f32_array). Square only, N multiple of 32.
fn metal_sgemm(a, b, c, m, n, k)
  s = METAL_SGEMM_STATE
  device = s[:device]
  a_buf = metal_buffer_for(device, a)
  b_buf = metal_buffer_for(device, b)
  c_buf = metal_buffer_for(device, c)
  n_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(n_buf, 0, n)
  n_tg = n / 32
  metal_dispatch_3d(s[:queue], s[:pipeline], [a_buf, b_buf, c_buf, n_buf], n_tg, n_tg, 1, 32, 1, 1)
