// nvfp4 batched matmul, multi-simdgroup TG. Each TG = 4 simdgroups
// (128 threads), computes an 8M × 32N output tile (4 sub-tiles of 8x8).
// All 4 simdgroups share one A tile (8M × K_TILE) loaded once per K
// step. Cuts activation reads ~4× vs the 1-simdgroup-per-TG variant.
//
// Dispatch (BATCH/8) * (N_ROWS/32) TGs of 128 threads.

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
kernel void nvfp4_matmul_simd_v2_fc(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const half  *__restrict__ x_h      [[buffer(2)]],
  device float       *__restrict__ y        [[buffer(3)]],
  threadgroup half *tg_w [[threadgroup(0)]],   // [32 outputs × 16 K]
  threadgroup half *tg_c [[threadgroup(1)]],   // [4 sub-tiles × 8 × 8] = 256 half
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
  int n_start = n_block_start + int(simd_id) * 8;  // each simdgroup → 8N sub-tile

  const int n_groups = K_DIM_FC / 16;
  const int u32s_per_row = K_DIM_FC / 8;

  simdgroup_matrix<half, 8, 8> C(0.0h);

  for (int g = 0; g < n_groups; g++) {
    // Cooperatively dequant 32 outputs × 16 K = 512 half. 128 threads → 4 each.
    for (int e = int(tid_in_tg); e < 512; e += 128) {
      int n_off = e / 16;       // 0..31
      int k_off = e % 16;       // 0..15
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
    // 2 sub-tiles of K=8.
    for (int sub = 0; sub < 2; sub++) {
      simdgroup_matrix<half, 8, 8> A;
      simdgroup_matrix<half, 8, 8> B;
      // A = x_h[m_start..m_start+8, k_global+sub*8..k_global+sub*8+8]
      // Loaded directly from device (each simdgroup loads same data; cache + broadcast).
      simdgroup_load(A,
                     x_h + m_start * K_DIM_FC + (k_global + sub * 8),
                     (ulong)K_DIM_FC);
      // B = transpose(tg_w[simd_id*8 .. simd_id*8+8, sub*8 .. sub*8+8])
      // tg_w stride = 16, origin offset = simd_id*8 row + sub*8 col.
      simdgroup_load(B,
                     (threadgroup half *)(tg_w + (int(simd_id) * 8) * 16 + sub * 8),
                     (ulong)16,
                     ulong2(0, 0),
                     true);
      simdgroup_multiply_accumulate(C, A, B, C);
    }
  }

  // Each simdgroup stores its 8×8 to its slot of tg_c, then writes to y.
  simdgroup_store(C, tg_c + int(simd_id) * 64, (ulong)8);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  // 256 cells per TG / 128 threads = 2 each.
  for (int e = int(tid_in_tg); e < 256; e += 128) {
    int sub = e / 64;
    int sub_e = e % 64;
    int r = sub_e / 8;
    int c = sub_e % 8;
    y[(m_start + r) * N_ROWS_FC + (n_block_start + sub * 8 + c)] = float(tg_c[sub * 64 + sub_e]);
  }
}
