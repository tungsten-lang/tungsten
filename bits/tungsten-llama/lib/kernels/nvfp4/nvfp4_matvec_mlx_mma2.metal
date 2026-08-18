// NVFP4 quantized GEMM v2 -- occupancy-corrected.
//
// v1 (nvfp4_matvec_mlx_mma.metal) validated at err 1e-6 and lost 4-10x. The
// cause was measured, not guessed: one simdgroup per 8 output rows issues a
// quarter of the memory requests the multi-row GEMV does, and this problem is
// bandwidth-bound, so latency hiding is the whole game. It also staged A and B
// through threadgroup memory behind full threadgroup barriers.
//
// v2 fixes exactly that:
//   * 4 simdgroups per threadgroup, each owning FOUR 8x8 accumulators = 32
//     output rows, so a threadgroup covers 128 output rows and every lane has a
//     weight load in flight every k-tile (128 per TG per tile vs v1's 8).
//   * each simdgroup stages into its OWN slice of threadgroup memory and syncs
//     with simdgroup_barrier only -- no cross-simdgroup barrier anywhere.
//   * 1.25 KB of threadgroup memory per simdgroup, 5 KB per threadgroup.
//
// Same scale handling as v1: the group scale is folded per value while staging,
// so this is NOT bit-exact with the GEMV (different summation order). err is
// reported against the production single-row qmv; the model gate is token ids.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

static inline half nvfp4_decode_half_mma2(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_mma2(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

constant int MMA2_NTILES = 4;   // 8x8 accumulators per simdgroup -> 32 rows
constant int MMA2_SGS    = 4;   // simdgroups per threadgroup     -> 128 rows

template <int M>
static inline void nvfp4_mma2_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int &k_dim,
  constant int &n_rows,
  constant float &global_scale,
  threadgroup float *tg,      // MMA2_SGS * 320 floats
  uint tg_id,
  uint simd_id,
  uint lane
) {
  const int rows_per_sg = MMA2_NTILES * 8;
  const int n0 = int(tg_id) * (MMA2_SGS * rows_per_sg) + int(simd_id) * rows_per_sg;
  if (n0 >= n_rows) return;

  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;

  threadgroup float *tgA = tg + int(simd_id) * 320;          // 64 floats
  threadgroup float *tgB = tgA + 64;                          // 256 floats

  simdgroup_float8x8 acc[MMA2_NTILES];
  for (int t = 0; t < MMA2_NTILES; ++t) acc[t] = simdgroup_float8x8(0.0f);

  const int n_tile  = int(lane) / 8;    // 0..3
  const int n_local = int(lane) % 8;    // 0..7

  for (int k0 = 0; k0 < k_dim; k0 += 8) {
    // ---- weights: one u32 per lane -> 8 decoded, scaled values -------------
    const int row = n0 + n_tile * 8 + n_local;
    if (row < n_rows) {
      const uint packed = w_packed[row * u32s_per_row + k0 / 8];
      const float s = float(e4m3_decode_half_mma2(
        uint(w_scales[row * n_groups + k0 / 16]))) * global_scale;
      for (int i = 0; i < 8; ++i) {
        const uint nib = (packed >> (4 * i)) & 0xf;
        tgB[(n_tile * 8 + i) * 8 + n_local] =
          float(nvfp4_decode_half_mma2(nib)) * s;
      }
    } else {
      for (int i = 0; i < 8; ++i) tgB[(n_tile * 8 + i) * 8 + n_local] = 0.0f;
    }

    // ---- activations: 64 entries over 32 lanes, zero past M ---------------
    for (int e = int(lane); e < 64; e += 32) {
      const int m = e / 8;
      const int kk = e - m * 8;
      const int kidx = k0 + kk;
      tgA[e] = (m < M && kidx < k_dim) ? x[m * k_dim + kidx] : 0.0f;
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);

    simdgroup_float8x8 A;
    simdgroup_load(A, tgA, 8);
    for (int t = 0; t < MMA2_NTILES; ++t) {
      simdgroup_float8x8 B;
      simdgroup_load(B, tgB + t * 64, 8);
      simdgroup_multiply_accumulate(acc[t], A, B, acc[t]);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }

  for (int t = 0; t < MMA2_NTILES; ++t) {
    simdgroup_store(acc[t], tgA, 8);
    simdgroup_barrier(mem_flags::mem_threadgroup);
    for (int e = int(lane); e < 64; e += 32) {
      const int m = e / 8;
      const int n = e - m * 8;
      const int out_row = n0 + t * 8 + n;
      if (m < M && out_row < n_rows) y[m * n_rows + out_row] = tgA[e];
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }
}

#define DEFINE_MMA2_KERNEL(NAME, M)                                         \
[[max_total_threads_per_threadgroup(128)]]                                  \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  threadgroup float shared[MMA2_SGS * 320];                                 \
  nvfp4_mma2_impl<M>(w, s, x, y, k, n, g, shared, tg, sg, sl);              \
}

DEFINE_MMA2_KERNEL(nvfp4_mma2_b3, 3)
DEFINE_MMA2_KERNEL(nvfp4_mma2_b4, 4)
DEFINE_MMA2_KERNEL(nvfp4_mma2_b5, 5)
