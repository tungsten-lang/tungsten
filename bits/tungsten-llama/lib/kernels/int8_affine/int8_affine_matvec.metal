// int8 affine matvec, MLX format. 8 output rows per TG (2 simdgroups × 4 rows).
// Used for low-rank gating projections in MoE models (router, shared_expert_gate)
// where MLX uses 8-bit unsigned affine quant (group=64, BF16 scales+biases)
// instead of nvfp4 to preserve top-K decision fidelity.
//
// Layout (weight matrix [N, K]):
//   weight: uint[N, K/4]   — 4 little-endian uint8 packed per u32
//   scales: bfloat[N, K/64] — BF16 per 64-element group
//   biases: bfloat[N, K/64] — BF16 per 64-element group
// Dequant: w[m, k] = scales[m, k/64] * uint8(byte) + biases[m, k/64]
//
// Dispatch: ceil(N / 8) TGs of 64 threads (2 simdgroups). Bounds-checked
// row writes — N doesn't have to be a multiple of 8 (handles N=1 for the
// shared_expert_gate too).
//
// K must be a multiple of 64 (group_size).

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(64)]]
kernel void int8_affine_matvec(
  device const uint   *__restrict__ weight [[buffer(0)]],
  device const bfloat *__restrict__ scales [[buffer(1)]],
  device const bfloat *__restrict__ biases [[buffer(2)]],
  device const float  *__restrict__ x      [[buffer(3)]],
  device float        *__restrict__ y      [[buffer(4)]],
  constant int &k_dim [[buffer(5)]],
  constant int &n_rows [[buffer(6)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int u32s_per_row = k_dim / 4;       // 4 uint8 per u32
  const int groups_per_row = k_dim / 64;    // group_size = 64

  int m_start = int(__tg_id) * 8 + int(__simd_id) * 4;
  int lane = int(__simd_lane);

  float r0 = 0.0f, r1 = 0.0f, r2 = 0.0f, r3 = 0.0f;

  // Lane-strided u32 walk. Each lane covers u32_idx ∈ {lane, lane+32, lane+64, ...}.
  // Each u32 holds 4 K-values, all in the same 64-element group (since
  // each u32 spans 4 K's and 4 < 64).
  for (int u32_block = 0; u32_block < u32s_per_row; u32_block += 32) {
    int u32_idx = u32_block + lane;
    if (u32_idx >= u32s_per_row) continue;

    int k_base = u32_idx * 4;
    int group_idx = k_base / 64;

    float x0 = x[k_base + 0];
    float x1 = x[k_base + 1];
    float x2 = x[k_base + 2];
    float x3 = x[k_base + 3];

#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      if (row < n_rows) {                                                 \
        uint w_packed = weight[row * u32s_per_row + u32_idx];             \
        float scale = float(scales[row * groups_per_row + group_idx]);    \
        float bias  = float(biases[row * groups_per_row + group_idx]);    \
        float w0 = scale * float((w_packed >>  0) & 0xFF) + bias;         \
        float w1 = scale * float((w_packed >>  8) & 0xFF) + bias;         \
        float w2 = scale * float((w_packed >> 16) & 0xFF) + bias;         \
        float w3 = scale * float((w_packed >> 24) & 0xFF) + bias;         \
        accum += w0 * x0 + w1 * x1 + w2 * x2 + w3 * x3;                   \
      }                                                                   \
    }

    DO_ROW(0, r0)
    DO_ROW(1, r1)
    DO_ROW(2, r2)
    DO_ROW(3, r3)
#undef DO_ROW
  }

  r0 = simd_sum(r0);
  r1 = simd_sum(r1);
  r2 = simd_sum(r2);
  r3 = simd_sum(r3);
  if (lane == 0) {
    if (m_start + 0 < n_rows) y[m_start + 0] = r0;
    if (m_start + 1 < n_rows) y[m_start + 1] = r1;
    if (m_start + 2 < n_rows) y[m_start + 2] = r2;
    if (m_start + 3 < n_rows) y[m_start + 3] = r3;
  }
}
