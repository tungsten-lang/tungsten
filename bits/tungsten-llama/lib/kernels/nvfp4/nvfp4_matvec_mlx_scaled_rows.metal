// Alternate row-groupings for the scaled MLX NVFP4 matvec autotuner.
// The production kernel uses 2 SIMD groups x 4 rows = 8 rows/TG. These
// entrypoints hold the arithmetic fixed and sweep 1 and 4 SIMD groups.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half_rows(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_rows(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

template <int SIMD_GROUPS>
static inline void nvfp4_matvec_mlx_scaled_rows_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant float &global_scale,
  uint tg_id,
  uint simd_id,
  uint simd_lane
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int row0 = int(tg_id) * (SIMD_GROUPS * 4) + int(simd_id) * 4;
  const int lane = int(simd_lane);
  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int g = g_block + lane;
    if (g >= n_groups) continue;
    const int x_off = g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    const float4 x0 = xp[0], x1 = xp[1], x2 = xp[2], x3 = xp[3];

#define DO_ROW(R, accum)                                                     \
    {                                                                        \
      const int row = row0 + (R);                                            \
      const uint w0 = w_packed[row * u32s_per_row + g * 2];                  \
      const uint w1 = w_packed[row * u32s_per_row + g * 2 + 1];              \
      const float scale = float(e4m3_decode_half_rows(                        \
        uint(w_scales[row * n_groups + g])));                                \
      const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;                    \
      const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;           \
      const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;                    \
      const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;           \
      const float4 wv0 = float4(nvfp4_decode_half_rows(b00 & 0xf),           \
        nvfp4_decode_half_rows(b00 >> 4), nvfp4_decode_half_rows(b01 & 0xf), \
        nvfp4_decode_half_rows(b01 >> 4));                                   \
      const float4 wv1 = float4(nvfp4_decode_half_rows(b02 & 0xf),           \
        nvfp4_decode_half_rows(b02 >> 4), nvfp4_decode_half_rows(b03 & 0xf), \
        nvfp4_decode_half_rows(b03 >> 4));                                   \
      const float4 wv2 = float4(nvfp4_decode_half_rows(b10 & 0xf),           \
        nvfp4_decode_half_rows(b10 >> 4), nvfp4_decode_half_rows(b11 & 0xf), \
        nvfp4_decode_half_rows(b11 >> 4));                                   \
      const float4 wv3 = float4(nvfp4_decode_half_rows(b12 & 0xf),           \
        nvfp4_decode_half_rows(b12 >> 4), nvfp4_decode_half_rows(b13 & 0xf), \
        nvfp4_decode_half_rows(b13 >> 4));                                   \
      accum += scale * (dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) +        \
        dot(wv3, x3));                                                       \
    }

    DO_ROW(0, result0)
    DO_ROW(1, result1)
    DO_ROW(2, result2)
    DO_ROW(3, result3)
#undef DO_ROW
  }

  result0 = simd_sum(result0) * global_scale;
  result1 = simd_sum(result1) * global_scale;
  result2 = simd_sum(result2) * global_scale;
  result3 = simd_sum(result3) * global_scale;
  if (lane == 0) {
    y[row0 + 0] = result0;
    y[row0 + 1] = result1;
    y[row0 + 2] = result2;
    y[row0 + 3] = result3;
  }
}

[[max_total_threads_per_threadgroup(32)]]
kernel void nvfp4_matvec_mlx_scaled_4r(
  device const uint  *w [[buffer(0)]],
  device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]],
  device float *y       [[buffer(3)]],
  constant int &k       [[buffer(4)]],
  constant float &g     [[buffer(5)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_rows_impl<1>(w, s, x, y, k, g, tg, sg, sl);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void nvfp4_matvec_mlx_scaled_16r(
  device const uint  *w [[buffer(0)]],
  device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]],
  device float *y       [[buffer(3)]],
  constant int &k       [[buffer(4)]],
  constant float &g     [[buffer(5)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_rows_impl<4>(w, s, x, y, k, g, tg, sg, sl);
}
