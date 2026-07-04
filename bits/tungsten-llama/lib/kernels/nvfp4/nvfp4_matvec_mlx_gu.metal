// Fused gate/up projection. One dispatch produces both matvec outputs
// from the same FFN-norm input vector. Saves 1 dispatch/layer of GPU
// fixed overhead vs two separate nvfp4_matvec_mlx calls.
//
// Dispatch: grid = (gate_tgs + up_tgs) TGs of 64 threads.
// TG layout: [Gate TGs | Up TGs]. For Lightning gate_tgs == up_tgs ==
// INTERMEDIATE/8, but we keep them as separate constants for flexibility.

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
kernel void nvfp4_matvec_mlx_gu(
  device const uint  *__restrict__ w_g [[buffer(0)]],
  device const uchar *__restrict__ s_g [[buffer(1)]],
  device const uint  *__restrict__ w_u [[buffer(2)]],
  device const uchar *__restrict__ s_u [[buffer(3)]],
  device const float *__restrict__ x   [[buffer(4)]],
  device float       *__restrict__ y_g [[buffer(5)]],
  device float       *__restrict__ y_u [[buffer(6)]],
  constant int &k_dim [[buffer(7)]],
  constant int &g_tgs [[buffer(8)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;

  int tg = int(__tg_id);
  device const uint  *w;
  device const uchar *s;
  device float       *y;
  int local_tg;
  if (tg < g_tgs) {
    w = w_g; s = s_g; y = y_g;
    local_tg = tg;
  } else {
    w = w_u; s = s_u; y = y_u;
    local_tg = tg - g_tgs;
  }

  int m_start = local_tg * 8 + int(__simd_id) * 4;
  int lane    = int(__simd_lane);

  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) continue;

    int x_off = g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      uint w0 = w[row * u32s_per_row + g * 2];                            \
      uint w1 = w[row * u32s_per_row + g * 2 + 1];                        \
      half scale_h = e4m3_decode_half(uint(s[row * n_groups + g]));       \
      float scale = float(scale_h);                                       \
      uint b00 = w0 & 0xFF, b01 = (w0 >>  8) & 0xFF;                      \
      uint b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;              \
      uint b10 = w1 & 0xFF, b11 = (w1 >>  8) & 0xFF;                      \
      uint b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;              \
      float4 wv0 = float4(                                                \
        nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4),        \
        nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));       \
      float4 wv1 = float4(                                                \
        nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4),        \
        nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));       \
      float4 wv2 = float4(                                                \
        nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4),        \
        nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));       \
      float4 wv3 = float4(                                                \
        nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4),        \
        nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));       \
      float dp = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3);\
      accum += scale * dp;                                                \
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
