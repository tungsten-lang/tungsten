// nvfp4 matvec, interleaved layout. Same TG shape as nvfp4_matvec_mlx
// (8 rows/TG, 2 simdgroups × 4 rows). Difference: weights and scales are
// packed per-group into a single buffer — each group is [1B scale | 8B
// quants] = 9 bytes, K/16 groups per row. Goal: single DRAM stream per
// row instead of two competing prefetcher streams (quants + scales).
//
// 9-byte stride is not u32-aligned. We read it as 9 individual uchar
// loads per group; the hardware coalesces these into a single cache-line
// access. Per-group cost is 9 uchars + 9 lane-relative ALU ops, vs the
// old 2 uint loads + 1 uchar load — net winner depends on whether the
// stream consolidation compensates for the byte shuffling.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_inter(
  device const uchar *__restrict__ packed [[buffer(0)]],   // [N × (K/16)*9] interleaved [scale|8B quants]
  device const float *__restrict__ x      [[buffer(1)]],   // [K] f32
  device float       *__restrict__ y      [[buffer(2)]],   // [N] f32
  constant int &k_dim [[buffer(3)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups   = k_dim / 16;
  const int row_stride = n_groups * 9;   // bytes per row

  int m_start = int(__tg_id) * 8 + int(__simd_id) * 4;
  int lane    = int(__simd_lane);

  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) continue;

    int x_off = g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

#define DO_ROW(R, accum)                                                    \
    {                                                                       \
      int row = m_start + (R);                                              \
      device const uchar *gp = packed + row * row_stride + g * 9;           \
      half scale_h = e4m3_decode_half(uint(gp[0]));                         \
      float scale = float(scale_h);                                         \
      uint b00 = uint(gp[1]); uint b01 = uint(gp[2]);                       \
      uint b02 = uint(gp[3]); uint b03 = uint(gp[4]);                       \
      uint b10 = uint(gp[5]); uint b11 = uint(gp[6]);                       \
      uint b12 = uint(gp[7]); uint b13 = uint(gp[8]);                       \
      float4 wv0 = float4(                                                  \
        nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4),          \
        nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));         \
      float4 wv1 = float4(                                                  \
        nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4),          \
        nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));         \
      float4 wv2 = float4(                                                  \
        nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4),          \
        nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));         \
      float4 wv3 = float4(                                                  \
        nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4),          \
        nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));         \
      float dp = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3); \
      accum += scale * dp;                                                  \
    }

    DO_ROW(0, result0)
    DO_ROW(1, result1)
    DO_ROW(2, result2)
    DO_ROW(3, result3)

#undef DO_ROW
  }

  result0 = simd_sum(result0);
  result1 = simd_sum(result1);
  result2 = simd_sum(result2);
  result3 = simd_sum(result3);
  if (lane == 0) {
    y[m_start + 0] = result0;
    y[m_start + 1] = result1;
    y[m_start + 2] = result2;
    y[m_start + 3] = result3;
  }
}
