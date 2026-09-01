// BF16 x f32 GEMM on simdgroup_matrix<float, 8, 8> — the prefill twin of
// nvfp4_gemm_f32. For chunked prefill the ORIGINAL bf16 checkpoint weights
// beat the NVFP4 sidecar: no nibble/scale decode ALU (which is what makes
// the nvfp4 GEMM compute-bound at ~5 GB/s effective), and the 2x bytes are
// amortized across the whole chunk. Same tile plan: each SIMD group owns 8
// output rows, 4 simdgroups per TG, K stepped 16 wide through threadgroup
// memory. Dispatch ceil(N/32) groups of 128 threads.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

static inline float bf16_gemm_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

template <int MT, bool ADD_RESIDUAL>
static inline void bf16_gemm_f32_impl(
  device const ushort *__restrict__ w,     // [N][K] bf16
  device const float  *__restrict__ x,     // [M][K] (at least MT*8 rows readable)
  device float        *__restrict__ y,     // [M][N]
  constant int   &k_dim,
  constant int   &n_rows,
  constant int   &m_rows,                  // valid activation rows (<= MT*8)
  threadgroup float *tile,                 // [4 simdgroups][8 rows][16 k]
  threadgroup float *stage,                // [4 simdgroups][8][8]
  uint tg_id, uint simd_id, uint lane
) {
  const int n0 = int(tg_id) * 32 + int(simd_id) * 8;
  if (n0 >= n_rows) return;
  const int n_groups = k_dim / 16;
  threadgroup float *bt = tile + int(simd_id) * 128;
  threadgroup float *st = stage + int(simd_id) * 64;

  const int r = int(lane) >> 2;
  const int q = int(lane) & 3;
  const int row = min(n0 + r, n_rows - 1);   // clamp: padded rows load harmlessly
  device const ushort *wrow = w + row * k_dim;

  simdgroup_matrix<float, 8, 8> C[MT];
#pragma clang loop unroll(full)
  for (int t = 0; t < MT; t++) C[t] = simdgroup_matrix<float, 8, 8>(0.0f);

  for (int g = 0; g < n_groups; g++) {
    device const ushort *wp = wrow + g * 16 + q * 4;
    threadgroup float *dst = bt + r * 16 + q * 4;
    dst[0] = bf16_gemm_to_f32(wp[0]);
    dst[1] = bf16_gemm_to_f32(wp[1]);
    dst[2] = bf16_gemm_to_f32(wp[2]);
    dst[3] = bf16_gemm_to_f32(wp[3]);
    simdgroup_barrier(mem_flags::mem_threadgroup);

    simdgroup_matrix<float, 8, 8> B0, B1;
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
    for (int e = int(lane); e < 64; e += 32) {
      const int m = t * 8 + (e >> 3);
      const int n = n0 + (e & 7);
      if (m < m_rows && n < n_rows) {
        if (ADD_RESIDUAL) y[m * n_rows + n] += st[e];
        else y[m * n_rows + n] = st[e];
      }
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }
}

#define DEFINE_BF16_GEMM(NAME, MT, RES)                                      \
[[max_total_threads_per_threadgroup(128)]]                                   \
kernel void NAME(                                                            \
  device const ushort *w [[buffer(0)]], device const float *x [[buffer(1)]], \
  device float *y [[buffer(2)]],                                             \
  constant int &k [[buffer(3)]], constant int &n [[buffer(4)]],              \
  constant int &m [[buffer(5)]],                                             \
  uint tg [[threadgroup_position_in_grid]],                                  \
  uint sg [[simdgroup_index_in_threadgroup]],                                \
  uint sl [[thread_index_in_simdgroup]]) {                                   \
  threadgroup float tile[4 * 128];                                           \
  threadgroup float stage[4 * 64];                                           \
  bf16_gemm_f32_impl<MT, RES>(w, x, y, k, n, m, tile, stage, tg, sg, sl);    \
}
DEFINE_BF16_GEMM(bf16_gemm_f32_m16, 2, false)
DEFINE_BF16_GEMM(bf16_gemm_f32_m32, 4, false)
DEFINE_BF16_GEMM(bf16_gemm_f32_m64, 8, false)
DEFINE_BF16_GEMM(bf16_gemm_f32_m128, 16, false)
#undef DEFINE_BF16_GEMM
