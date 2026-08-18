// NVFP4 quantized GEMM for wide verification, using simdgroup matrix hardware.
//
// Why: the multi-row GEMV in nvfp4_matvec_mlx_scaled_wide.metal is
// bandwidth-bound up to width 3 (row ladder 32/35/37 ms in-situ) and turns
// compute-bound at width 4 (+22% time for +33% work; 45 ms). That is what makes
// draft depth 3 a wash. MLX/Ollama do not hit this wall because for multi-row
// they dispatch a GEMM, and the MMA units make the arithmetic effectively free
// so the kernel stays on its bandwidth floor as width grows.
//
// Shape: one simdgroup owns an 8(N-outputs) x 8(M-tokens) accumulator and walks
// K in blocks of 32 (four 8-wide k-tiles). Per block each of the 32 lanes loads
// exactly one u32 of packed weights (8 output rows x 4 k-tiles), decodes its 8
// nibbles, folds in the group scale, and stages them; activations are staged
// too, zero-filled past M so a width-4 call is safe against an x buffer that
// only holds 4 rows.
//
// NOT bit-exact with the GEMV: the group scale is folded per value instead of
// once per 16-value group, so the summation order differs. The bakeoff reports
// err against the production single-row qmv; the model-level gate is emitted
// token ids.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

static inline half nvfp4_decode_half_mma(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_mma(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

template <int M>
static inline void nvfp4_mma_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int &k_dim,
  constant int &n_rows,
  constant float &global_scale,
  threadgroup float *tgA,   // [4][8][8]  (k-tile, m, k)
  threadgroup float *tgB,   // [4][8][8]  (k-tile, k, n)
  uint tg_id,
  uint lane
) {
  const int n0 = int(tg_id) * 8;
  if (n0 >= n_rows) return;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;

  simdgroup_float8x8 acc = simdgroup_float8x8(0.0f);

  const int n_local = int(lane) / 4;   // 0..7  output row within tile
  const int t_lane  = int(lane) % 4;   // 0..3  k-tile within the 32-wide block

  for (int k0 = 0; k0 < k_dim; k0 += 32) {
    // ---- stage weights: one u32 per lane -> 8 decoded, scaled values -------
    const int row = n0 + n_local;
    const int k_tile0 = k0 + t_lane * 8;
    if (row < n_rows && k_tile0 < k_dim) {
      const uint packed = w_packed[row * u32s_per_row + k_tile0 / 8];
      const float s = float(e4m3_decode_half_mma(
        uint(w_scales[row * n_groups + k_tile0 / 16]))) * global_scale;
      for (int i = 0; i < 8; ++i) {
        const uint nib = (packed >> (4 * i)) & 0xf;
        tgB[(t_lane * 8 + i) * 8 + n_local] =
          float(nvfp4_decode_half_mma(nib)) * s;
      }
    } else {
      for (int i = 0; i < 8; ++i) tgB[(t_lane * 8 + i) * 8 + n_local] = 0.0f;
    }

    // ---- stage activations: zero past M ------------------------------------
    // 4 tiles * 8 m * 8 k = 256 entries over 32 lanes = 8 each.
    for (int e = int(lane); e < 256; e += 32) {
      const int t = e / 64;
      const int m = (e - t * 64) / 8;
      const int kk = e - t * 64 - m * 8;
      const int kidx = k0 + t * 8 + kk;
      float v = 0.0f;
      if (m < M && kidx < k_dim) v = x[m * k_dim + kidx];
      tgA[(t * 8 + m) * 8 + kk] = v;
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);

    for (int t = 0; t < 4; ++t) {
      simdgroup_float8x8 A, B;
      simdgroup_load(A, tgA + t * 64, 8);
      simdgroup_load(B, tgB + t * 64, 8);
      simdgroup_multiply_accumulate(acc, A, B, acc);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }

  // C[m][n] -> y[m * n_rows + n0 + n]
  simdgroup_store(acc, tgA, 8);
  simdgroup_barrier(mem_flags::mem_threadgroup);
  for (int e = int(lane); e < 64; e += 32) {
    const int m = e / 8;
    const int n = e - m * 8;
    if (m < M && (n0 + n) < n_rows) {
      y[m * n_rows + n0 + n] = tgA[m * 8 + n];
    }
  }
}

#define DEFINE_MMA_KERNEL(NAME, M)                                          \
[[max_total_threads_per_threadgroup(32)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  threadgroup float tgA[256];                                               \
  threadgroup float tgB[256];                                               \
  nvfp4_mma_impl<M>(w, s, x, y, k, n, g, tgA, tgB, tg, sl);                 \
}

DEFINE_MMA_KERNEL(nvfp4_mma_b3, 3)
DEFINE_MMA_KERNEL(nvfp4_mma_b4, 4)
DEFINE_MMA_KERNEL(nvfp4_mma_b5, 5)
