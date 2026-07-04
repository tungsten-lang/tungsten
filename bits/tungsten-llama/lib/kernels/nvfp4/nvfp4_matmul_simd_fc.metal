// nvfp4 batched matmul using Apple simdgroup_matrix<half, 8, 8>.
// Each TG = 1 simdgroup (32 threads), computes one 8M × 8N output tile.
// For each K_TILE=16 (one nvfp4 group): cooperatively dequant 8 rows × 16
// K positions of W into half TG memory (pre-scaled), then 2 simdgroup
// 8x8x8 multiply-accumulates against pre-converted half X.
//
// X is pre-converted to half by f32_to_f16_batch.metal before this runs.
//
// Dispatch (BATCH/8) * (N_ROWS/8) TGs of 32 threads. Both BATCH and
// N_ROWS must be multiples of 8.

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

kernel void nvfp4_matmul_simd_fc(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const half  *__restrict__ x_h      [[buffer(2)]],   // [BATCH × K_DIM] half
  device float       *__restrict__ y        [[buffer(3)]],   // [BATCH × N_ROWS] float
  threadgroup half *tg_w [[threadgroup(0)]],                  // [8 × 16]
  threadgroup half *tg_c [[threadgroup(1)]],                  // [8 × 8]
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  const int n_tiles_per_row = N_ROWS_FC / 8;
  int n_tile = int(tg) % n_tiles_per_row;
  int m_tile = int(tg) / n_tiles_per_row;
  if (m_tile >= BATCH_FC / 8) return;

  int m_start = m_tile * 8;
  int n_start = n_tile * 8;

  const int n_groups = K_DIM_FC / 16;
  const int u32s_per_row = K_DIM_FC / 8;

  simdgroup_matrix<half, 8, 8> C(0.0h);

  for (int g = 0; g < n_groups; g++) {
    // Cooperatively dequant 8 outputs × 16 K positions = 128 half values.
    // 32 lanes → 4 elems per lane.
    for (int e = int(lane); e < 128; e += 32) {
      int n_off = e / 16;       // 0..7
      int k_off = e % 16;       // 0..15
      int row = n_start + n_off;
      int word_idx = k_off / 8;     // 0 or 1
      int byte_idx = (k_off % 8) / 2;
      int nibble_lo = ((k_off % 8) % 2) == 0;
      uint w = w_packed[row * u32s_per_row + g * 2 + word_idx];
      uint b = (w >> (byte_idx * 8)) & 0xFF;
      uint nibble = nibble_lo ? (b & 0xF) : (b >> 4);
      float s = e4m3_decode(uint(w_scales[row * n_groups + g]));
      tg_w[n_off * 16 + k_off] = half(NVFP4_TABLE[nibble] * s);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);

    int k_global = g * 16;
    // 2 sub-tiles of K=8 each.
    for (int sub = 0; sub < 2; sub++) {
      simdgroup_matrix<half, 8, 8> A;
      simdgroup_matrix<half, 8, 8> B;
      // A: x_h[m_start..m_start+8, k_global+sub*8..k_global+sub*8+8]
      // src layout row-major, stride = K_DIM_FC
      simdgroup_load(A,
                     x_h + m_start * K_DIM_FC + (k_global + sub * 8),
                     (ulong)K_DIM_FC);
      // B: tg_w transposed view at column offset sub*8
      // tg_w is laid out [8 rows × 16 cols], we want B[k=0..7, n=0..7] = tg_w[n][sub*8 + k]
      // So src = &tg_w[0 + sub*8], stride = 16, transpose=true
      simdgroup_load(B,
                     (threadgroup half *)(tg_w + sub * 8),
                     (ulong)16,
                     ulong2(0, 0),
                     true);
      simdgroup_multiply_accumulate(C, A, B, C);
    }
  }

  // Store C as float into y[m_start..m_start+8, n_start..n_start+8] via half scratch
  simdgroup_store(C, tg_c, (ulong)8);
  simdgroup_barrier(mem_flags::mem_threadgroup);
  // 64 elems / 32 lanes = 2 per lane
  for (int e = int(lane); e < 64; e += 32) {
    int r = e / 8;
    int c = e % 8;
    y[(m_start + r) * N_ROWS_FC + (n_start + c)] = float(tg_c[r * 8 + c]);
  }
}
