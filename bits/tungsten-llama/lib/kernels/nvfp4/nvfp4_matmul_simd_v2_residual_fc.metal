// nvfp4 batched matmul + residual, multi-simdgroup TG. Same shape as
// nvfp4_matmul_simd_v2_fc but final store does y[r,c] += float(C[r,c]).

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

constant float NVFP4_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,
     2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f,
    -2.0f, -3.0f, -4.0f, -6.0f,
};

static inline float e4m3_decode(uint b) {
    uint s = (b >> 7) & 0x1;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    float sign = s ? -1.0f : 1.0f;
    if (e == 0) return sign * float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7) return 0.0f;
    float mantissa = 1.0f + float(m) * 0.125f;
    return sign * exp2(float(int(e) - 7)) * mantissa;
}

[[max_total_threads_per_threadgroup(128)]]
kernel void nvfp4_matmul_simd_v2_residual_fc(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const half  *__restrict__ x_h      [[buffer(2)]],
  device float       *__restrict__ y        [[buffer(3)]],
  threadgroup half *tg_w [[threadgroup(0)]],
  threadgroup half *tg_c [[threadgroup(1)]],
  uint tid_in_tg [[thread_position_in_threadgroup]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd_id [[simdgroup_index_in_threadgroup]]
) {
  const int n_tiles_per_row = N_ROWS_FC / 32;
  int n_tile_block = int(tg) % n_tiles_per_row;
  int m_tile = int(tg) / n_tiles_per_row;
  if (m_tile >= BATCH_FC / 8) return;

  int m_start = m_tile * 8;
  int n_block_start = n_tile_block * 32;

  const int n_groups = K_DIM_FC / 16;
  const int u32s_per_row = K_DIM_FC / 8;

  simdgroup_matrix<half, 8, 8> C(0.0h);

  for (int g = 0; g < n_groups; g++) {
    for (int e = int(tid_in_tg); e < 512; e += 128) {
      int n_off = e / 16;
      int k_off = e % 16;
      int row = n_block_start + n_off;
      int word_idx = k_off / 8;
      int byte_idx = (k_off % 8) / 2;
      int nibble_lo = ((k_off % 8) % 2) == 0;
      uint w = w_packed[row * u32s_per_row + g * 2 + word_idx];
      uint b = (w >> (byte_idx * 8)) & 0xFF;
      uint nibble = nibble_lo ? (b & 0xF) : (b >> 4);
      float s = e4m3_decode(uint(w_scales[row * n_groups + g]));
      tg_w[n_off * 16 + k_off] = half(NVFP4_TABLE[nibble] * s);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    int k_global = g * 16;
    for (int sub = 0; sub < 2; sub++) {
      simdgroup_matrix<half, 8, 8> A;
      simdgroup_matrix<half, 8, 8> B;
      simdgroup_load(A, x_h + m_start * K_DIM_FC + (k_global + sub * 8), (ulong)K_DIM_FC);
      simdgroup_load(B, (threadgroup half *)(tg_w + (int(simd_id) * 8) * 16 + sub * 8), (ulong)16, ulong2(0, 0), true);
      simdgroup_multiply_accumulate(C, A, B, C);
    }
  }

  simdgroup_store(C, tg_c + int(simd_id) * 64, (ulong)8);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int e = int(tid_in_tg); e < 256; e += 128) {
    int sub = e / 64;
    int sub_e = e % 64;
    int r = sub_e / 8;
    int c = sub_e % 8;
    y[(m_start + r) * N_ROWS_FC + (n_block_start + sub * 8 + c)] += float(tg_c[sub * 64 + sub_e]);
  }
}
