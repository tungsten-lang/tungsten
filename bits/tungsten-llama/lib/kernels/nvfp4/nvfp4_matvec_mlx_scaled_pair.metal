// Two-token MLX NVFP4 matrix-vector product. Each packed weight/scaling
// group is loaded and decoded once, then dotted with both activation rows.
// This is the MTP-1 verification primitive: compared with two independent
// qmv dispatches it halves weight traffic while preserving f32 accumulation.
//
// Dispatch: ceil(N_ROWS / 4) TGs of 64 threads. K must be a multiple of 16.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half_pair(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_pair(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

template <bool ADD_RESIDUAL>
static inline void nvfp4_matvec_mlx_scaled_pair_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  uint tg_id,
  uint simd_id,
  uint simd_lane
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int row0 = int(tg_id) * 4 + int(simd_id) * 2;
  const int lane = int(simd_lane);

  float r00 = 0.0f, r01 = 0.0f;
  float r10 = 0.0f, r11 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int g = g_block + lane;
    if (g >= n_groups) continue;

    const int x_off = g * 16;
    device const float4 *x0p = (device const float4 *)(&x[x_off]);
    device const float4 *x1p = (device const float4 *)(&x[k_dim + x_off]);
    const float4 x00 = x0p[0], x01 = x0p[1], x02 = x0p[2], x03 = x0p[3];
    const float4 x10 = x1p[0], x11 = x1p[1], x12 = x1p[2], x13 = x1p[3];

#define DO_PAIR_ROW(ROW, A0, A1)                                             \
    if ((ROW) < n_rows) {                                                    \
      const uint w0 = w_packed[(ROW) * u32s_per_row + g * 2];                \
      const uint w1 = w_packed[(ROW) * u32s_per_row + g * 2 + 1];            \
      const float s = float(e4m3_decode_half_pair(                            \
        uint(w_scales[(ROW) * n_groups + g])));                              \
      const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;                    \
      const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;           \
      const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;                    \
      const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;           \
      const float4 wv0 = float4(nvfp4_decode_half_pair(b00 & 0xf),           \
        nvfp4_decode_half_pair(b00 >> 4), nvfp4_decode_half_pair(b01 & 0xf), \
        nvfp4_decode_half_pair(b01 >> 4));                                   \
      const float4 wv1 = float4(nvfp4_decode_half_pair(b02 & 0xf),           \
        nvfp4_decode_half_pair(b02 >> 4), nvfp4_decode_half_pair(b03 & 0xf), \
        nvfp4_decode_half_pair(b03 >> 4));                                   \
      const float4 wv2 = float4(nvfp4_decode_half_pair(b10 & 0xf),           \
        nvfp4_decode_half_pair(b10 >> 4), nvfp4_decode_half_pair(b11 & 0xf), \
        nvfp4_decode_half_pair(b11 >> 4));                                   \
      const float4 wv3 = float4(nvfp4_decode_half_pair(b12 & 0xf),           \
        nvfp4_decode_half_pair(b12 >> 4), nvfp4_decode_half_pair(b13 & 0xf), \
        nvfp4_decode_half_pair(b13 >> 4));                                   \
      (A0) += s * (dot(wv0, x00) + dot(wv1, x01) + dot(wv2, x02) + dot(wv3, x03)); \
      (A1) += s * (dot(wv0, x10) + dot(wv1, x11) + dot(wv2, x12) + dot(wv3, x13)); \
    }

    DO_PAIR_ROW(row0 + 0, r00, r01)
    DO_PAIR_ROW(row0 + 1, r10, r11)
#undef DO_PAIR_ROW
  }

  r00 = simd_sum(r00) * global_scale;
  r01 = simd_sum(r01) * global_scale;
  r10 = simd_sum(r10) * global_scale;
  r11 = simd_sum(r11) * global_scale;

  if (lane == 0) {
    if (row0 + 0 < n_rows) {
      if constexpr (ADD_RESIDUAL) {
        y[row0 + 0] += r00;
        y[n_rows + row0 + 0] += r01;
      } else {
        y[row0 + 0] = r00;
        y[n_rows + row0 + 0] = r01;
      }
    }
    if (row0 + 1 < n_rows) {
      if constexpr (ADD_RESIDUAL) {
        y[row0 + 1] += r10;
        y[n_rows + row0 + 1] += r11;
      } else {
        y[row0 + 1] = r10;
        y[n_rows + row0 + 1] = r11;
      }
    }
  }
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_pair(
  device const uint  *w [[buffer(0)]],
  device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]],
  device float *y       [[buffer(3)]],
  constant int &k       [[buffer(4)]],
  constant int &n       [[buffer(5)]],
  constant float &g     [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_pair_impl<false>(w, s, x, y, k, n, g, tg, sg, sl);
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_pair_residual(
  device const uint  *w [[buffer(0)]],
  device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]],
  device float *y       [[buffer(3)]],
  constant int &k       [[buffer(4)]],
  constant int &n       [[buffer(5)]],
  constant float &g     [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_pair_impl<true>(w, s, x, y, k, n, g, tg, sg, sl);
}

// Lower-register candidate: one output row per SIMD group (two rows/TG).
// Kept as a distinct entry point so the model autotuner can select it for
// unusually register-sensitive shapes without penalizing the common case.
[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_pair_r1(
  device const uint  *w_packed [[buffer(0)]],
  device const uchar *w_scales [[buffer(1)]],
  device const float *x        [[buffer(2)]],
  device float *y              [[buffer(3)]],
  constant int &k_dim          [[buffer(4)]],
  constant int &n_rows         [[buffer(5)]],
  constant float &global_scale [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint simd_id [[simdgroup_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]]) {
  const int row = int(tg) * 2 + int(simd_id);
  if (row >= n_rows) return;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  float a0 = 0.0f, a1 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int group = g_block + int(lane);
    if (group >= n_groups) continue;
    const int x_off = group * 16;
    device const float4 *x0p = (device const float4 *)(&x[x_off]);
    device const float4 *x1p = (device const float4 *)(&x[k_dim + x_off]);
    const uint w0 = w_packed[row * u32s_per_row + group * 2];
    const uint w1 = w_packed[row * u32s_per_row + group * 2 + 1];
    const float s = float(e4m3_decode_half_pair(
      uint(w_scales[row * n_groups + group])));
    const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
    const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
    const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
    const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
    const float4 wv0 = float4(nvfp4_decode_half_pair(b00 & 0xf),
      nvfp4_decode_half_pair(b00 >> 4), nvfp4_decode_half_pair(b01 & 0xf),
      nvfp4_decode_half_pair(b01 >> 4));
    const float4 wv1 = float4(nvfp4_decode_half_pair(b02 & 0xf),
      nvfp4_decode_half_pair(b02 >> 4), nvfp4_decode_half_pair(b03 & 0xf),
      nvfp4_decode_half_pair(b03 >> 4));
    const float4 wv2 = float4(nvfp4_decode_half_pair(b10 & 0xf),
      nvfp4_decode_half_pair(b10 >> 4), nvfp4_decode_half_pair(b11 & 0xf),
      nvfp4_decode_half_pair(b11 >> 4));
    const float4 wv3 = float4(nvfp4_decode_half_pair(b12 & 0xf),
      nvfp4_decode_half_pair(b12 >> 4), nvfp4_decode_half_pair(b13 & 0xf),
      nvfp4_decode_half_pair(b13 >> 4));
    const float d0 = dot(wv0, x0p[0]) + dot(wv1, x0p[1]) +
      dot(wv2, x0p[2]) + dot(wv3, x0p[3]);
    const float d1 = dot(wv0, x1p[0]) + dot(wv1, x1p[1]) +
      dot(wv2, x1p[2]) + dot(wv3, x1p[3]);
    a0 += s * d0;
    a1 += s * d1;
  }
  a0 = simd_sum(a0) * global_scale;
  a1 = simd_sum(a1) * global_scale;
  if (lane == 0) {
    y[row] = a0;
    y[n_rows + row] = a1;
  }
}
