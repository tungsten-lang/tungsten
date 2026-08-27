// NVFP4 x f32 GEMM on simdgroup_matrix<float, 8, 8> for small M (block
// verify, M <= 8 per tile; up to 8 tiles = 64 rows for prefill).
//
// Why: the exact cross-row GEMV goes ALU-bound past 4 activation rows (the
// measured width ladder is 36/39/44/55/67/112/133/105 ms for widths 1..8 --
// eight rows of scalar FMAs per nibble). This kernel keeps the per-weight
// work at ONE nibble decode and hands the M x 8 x 8 multiply-accumulate to
// the matrix unit, so M=8 should cost little more than M=1.
//
// Numerics: weights are decoded to exact f32 (table value x E4M3 group
// scale, both exactly representable), activations are f32, accumulation is
// f32, and the per-tensor global_scale is applied once at the end -- the
// same value set the GEMV consumes, so results agree to f32 reassociation
// (the 8-wide dot inside the MMA sums in hardware order). NOT bit-identical
// to the GEMV: use it as a measured arm, gate it on ids/near-tie stats.
//
// Tile: each SIMD group owns 8 output rows (N); a threadgroup of 4 SIMD
// groups covers 32 rows. Per K step of 16 (one NVFP4 group): the 32 lanes
// decode the 8x16 weight tile into threadgroup memory (4 nibbles per lane),
// then two 8x8 MMAs per M tile. Dispatch ceil(N/32) groups of 128 threads.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant float NVFP4_GEMM_TABLE[16] = {
   0.0f,  0.5f,  1.0f,  1.5f,  2.0f,  3.0f,  4.0f,  6.0f,
  -0.0f, -0.5f, -1.0f, -1.5f, -2.0f, -3.0f, -4.0f, -6.0f,
};

static inline float e4m3_gemm_decode(uint b) {
  return float(as_type<half>(ushort((b & 127) << 7)) * 256.0h);
}

template <int MT, bool ADD_RESIDUAL>
static inline void nvfp4_gemm_f32_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,      // [M][K] (at least MT*8 rows readable)
  device float       *__restrict__ y,      // [M][N]
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  constant int   &m_rows,                  // valid activation rows (<= MT*8)
  threadgroup float *tile,                 // [4 simdgroups][8 rows][16 k]
  threadgroup float *stage,                // [4 simdgroups][8][8]
  uint tg_id, uint simd_id, uint lane
) {
  const int n0 = int(tg_id) * 32 + int(simd_id) * 8;
  if (n0 >= n_rows) return;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  threadgroup float *bt = tile + int(simd_id) * 128;
  threadgroup float *st = stage + int(simd_id) * 64;

  // Lane -> (row r = lane/4, quarter q = lane%4): nibbles 4q..4q+3 of the row's
  // 16-wide group live in u32 (q >> 1), bytes (q & 1) * 2 and + 1.
  const int r = int(lane) >> 2;
  const int q = int(lane) & 3;
  const int row = min(n0 + r, n_rows - 1);   // clamp: padded rows decode harmlessly
  device const uint *wrow = w_packed + row * u32s_per_row;
  device const uchar *srow = w_scales + row * n_groups;

  simdgroup_matrix<float, 8, 8> C[MT];
#pragma clang loop unroll(full)
  for (int t = 0; t < MT; t++) C[t] = simdgroup_matrix<float, 8, 8>(0.0f);

  for (int g = 0; g < n_groups; g++) {
    const uint w = wrow[g * 2 + (q >> 1)];
    const uint b0 = (w >> ((q & 1) * 16)) & 0xff;
    const uint b1 = (w >> ((q & 1) * 16 + 8)) & 0xff;
    const float s = e4m3_gemm_decode(uint(srow[g]));
    threadgroup float *dst = bt + r * 16 + q * 4;
    dst[0] = NVFP4_GEMM_TABLE[b0 & 0xf] * s;
    dst[1] = NVFP4_GEMM_TABLE[b0 >> 4] * s;
    dst[2] = NVFP4_GEMM_TABLE[b1 & 0xf] * s;
    dst[3] = NVFP4_GEMM_TABLE[b1 >> 4] * s;
    simdgroup_barrier(mem_flags::mem_threadgroup);

    simdgroup_matrix<float, 8, 8> B0, B1;
    // B[k][n] = W[n][k]: the tile is [n][k] row-major (stride 16) -> transpose.
    simdgroup_load(B0, bt, 16, ulong2(0, 0), true);
    simdgroup_load(B1, bt + 8, 16, ulong2(0, 0), true);
    const int k0 = g * 16;
#pragma clang loop unroll(full)
    for (int t = 0; t < MT; t++) {
      simdgroup_matrix<float, 8, 8> A0, A1;
      simdgroup_load(A0, x + (t * 8) * k_dim + k0, (ulong)k_dim);
      simdgroup_load(A1, x + (t * 8) * k_dim + k0 + 8, (ulong)k_dim);
      simdgroup_multiply_accumulate(C[t], A0, B0, C[t]);
      simdgroup_multiply_accumulate(C[t], A1, B1, C[t]);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }

#pragma clang loop unroll(full)
  for (int t = 0; t < MT; t++) {
    simdgroup_store(C[t], st, 8);
    simdgroup_barrier(mem_flags::mem_threadgroup);
    // 64 cells, 32 lanes -> 2 each: cell = m * 8 + n_local.
    for (int e = int(lane); e < 64; e += 32) {
      const int m = t * 8 + (e >> 3);
      const int n = n0 + (e & 7);
      if (m < m_rows && n < n_rows) {
        const float v = st[e] * global_scale;
        if (ADD_RESIDUAL) y[m * n_rows + n] += v;
        else y[m * n_rows + n] = v;
      }
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }
}

#define DEFINE_NVFP4_GEMM(NAME, MT, RES)                                     \
[[max_total_threads_per_threadgroup(128)]]                                   \
kernel void NAME(                                                            \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],   \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],        \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],              \
  constant float &g [[buffer(6)]], constant int &m [[buffer(7)]],            \
  uint tg [[threadgroup_position_in_grid]],                                  \
  uint sg [[simdgroup_index_in_threadgroup]],                                \
  uint sl [[thread_index_in_simdgroup]]) {                                   \
  threadgroup float tile[4 * 128];                                           \
  threadgroup float stage[4 * 64];                                           \
  nvfp4_gemm_f32_impl<MT, RES>(w, s, x, y, k, n, g, m, tile, stage, tg, sg, sl); \
}
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m8, 1, false)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m8_residual, 1, true)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m16, 2, false)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m16_residual, 2, true)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m32, 4, false)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m32_residual, 4, true)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m64, 8, false)
DEFINE_NVFP4_GEMM(nvfp4_gemm_f32_m64_residual, 8, true)
#undef DEFINE_NVFP4_GEMM
