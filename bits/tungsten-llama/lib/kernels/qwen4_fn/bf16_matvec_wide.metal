// Multi-row bf16 matvec family for Qwen3.8-Flash-Next's bf16-heavy decode
// (GDN in/out projections, attention q/k/v/o, HC mixers, lm_head stream
// ~9.7 GB/token). The shared bf16_matvec is one row per 32-lane simdgroup;
// these amortize activation loads across R rows per simdgroup and read
// weights as ushort4 (8B per lane-step) to keep the stream saturated.
//
//   y[m] = dot(w[m, :], x[:])
//
// Variants: 2 simdgroups per TG, R in {2, 4}; grid covers n_rows/(2*R) TGs
// of 64 threads. k_dim must be a multiple of 128 (all shapes here are).
//
// Dispatch: metal_dispatch_groups(queue, pipe, [w, x, y, k_dim, n_rows],
//                                 (n_rows + 2*R - 1) / (2*R), 64)

#include <metal_stdlib>
using namespace metal;

static inline float bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

static inline float4 bf16x4_to_f32(ushort4 v) {
  return float4(bf16_to_f32(v.x), bf16_to_f32(v.y),
                bf16_to_f32(v.z), bf16_to_f32(v.w));
}

#define BF16_WIDE_KERNEL(NAME, R)                                            \
[[max_total_threads_per_threadgroup(64)]]                                    \
kernel void NAME(                                                            \
  device const ushort *__restrict__ w [[buffer(0)]],                         \
  device const float  *__restrict__ x [[buffer(1)]],                         \
  device float        *__restrict__ y [[buffer(2)]],                         \
  constant int &k_dim  [[buffer(3)]],                                        \
  constant int &n_rows [[buffer(4)]],                                        \
  uint __tg_id     [[threadgroup_position_in_grid]],                         \
  uint __simd_id   [[simdgroup_index_in_threadgroup]],                       \
  uint __simd_lane [[thread_index_in_simdgroup]]                             \
) {                                                                          \
  int m0 = (int(__tg_id) * 2 + int(__simd_id)) * (R);                        \
  int lane = int(__simd_lane);                                               \
  float acc[R];                                                              \
  for (int r = 0; r < (R); r++) acc[r] = 0.0f;                               \
  for (int i = lane * 4; i < k_dim; i += 32 * 4) {                           \
    float4 xv = *(device const float4 *)(&x[i]);                             \
    for (int r = 0; r < (R); r++) {                                          \
      int row = m0 + r;                                                      \
      if (row >= n_rows) continue;                                           \
      ushort4 wv = *(device const ushort4 *)(&w[row * k_dim + i]);           \
      acc[r] += dot(bf16x4_to_f32(wv), xv);                                  \
    }                                                                        \
  }                                                                          \
  for (int r = 0; r < (R); r++) {                                            \
    float total = simd_sum(acc[r]);                                          \
    int row = m0 + r;                                                        \
    if (lane == 0 && row < n_rows) y[row] = total;                           \
  }                                                                          \
}

BF16_WIDE_KERNEL(bf16_matvec_w2, 2)
BF16_WIDE_KERNEL(bf16_matvec_w4, 4)
#undef BF16_WIDE_KERNEL
