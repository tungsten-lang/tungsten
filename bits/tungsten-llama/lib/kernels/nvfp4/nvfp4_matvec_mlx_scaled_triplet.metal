// Three-token MLX NVFP4 matrix-vector product for MTP-2 verification.
// Packed weights and scales are loaded once and dotted with all three rows.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half_triplet(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_triplet(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

template <bool ADD_RESIDUAL>
static inline void nvfp4_matvec_mlx_scaled_triplet_impl(
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

  float r00 = 0.0f, r01 = 0.0f, r02 = 0.0f;
  float r10 = 0.0f, r11 = 0.0f, r12 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int g = g_block + lane;
    if (g >= n_groups) continue;
    const int x_off = g * 16;
    device const float4 *x0 = (device const float4 *)(&x[x_off]);
    device const float4 *x1 = (device const float4 *)(&x[k_dim + x_off]);
    device const float4 *x2 = (device const float4 *)(&x[2 * k_dim + x_off]);

#define DO_TRIPLET_ROW(ROW, A0, A1, A2)                                     \
    if ((ROW) < n_rows) {                                                    \
      const uint w0 = w_packed[(ROW) * u32s_per_row + g * 2];                \
      const float s = float(e4m3_decode_half_triplet(                         \
        uint(w_scales[(ROW) * n_groups + g])));                              \
      const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;                    \
      const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;           \
      const float4 v0 = float4(nvfp4_decode_half_triplet(b00 & 0xf),         \
        nvfp4_decode_half_triplet(b00 >> 4),                                 \
        nvfp4_decode_half_triplet(b01 & 0xf),                                \
        nvfp4_decode_half_triplet(b01 >> 4));                                \
      const float4 v1 = float4(nvfp4_decode_half_triplet(b02 & 0xf),         \
        nvfp4_decode_half_triplet(b02 >> 4),                                 \
        nvfp4_decode_half_triplet(b03 & 0xf),                                \
        nvfp4_decode_half_triplet(b03 >> 4));                                \
      float d0 = dot(v0, x0[0]) + dot(v1, x0[1]);                            \
      float d1 = dot(v0, x1[0]) + dot(v1, x1[1]);                            \
      float d2 = dot(v0, x2[0]) + dot(v1, x2[1]);                            \
      const uint w1 = w_packed[(ROW) * u32s_per_row + g * 2 + 1];            \
      const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;                    \
      const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;           \
      const float4 v2 = float4(nvfp4_decode_half_triplet(b10 & 0xf),         \
        nvfp4_decode_half_triplet(b10 >> 4),                                 \
        nvfp4_decode_half_triplet(b11 & 0xf),                                \
        nvfp4_decode_half_triplet(b11 >> 4));                                \
      const float4 v3 = float4(nvfp4_decode_half_triplet(b12 & 0xf),         \
        nvfp4_decode_half_triplet(b12 >> 4),                                 \
        nvfp4_decode_half_triplet(b13 & 0xf),                                \
        nvfp4_decode_half_triplet(b13 >> 4));                                \
      d0 += dot(v2, x0[2]) + dot(v3, x0[3]);                                 \
      d1 += dot(v2, x1[2]) + dot(v3, x1[3]);                                 \
      d2 += dot(v2, x2[2]) + dot(v3, x2[3]);                                 \
      (A0) += s * d0; (A1) += s * d1; (A2) += s * d2;                       \
    }

    DO_TRIPLET_ROW(row0 + 0, r00, r01, r02)
    DO_TRIPLET_ROW(row0 + 1, r10, r11, r12)
#undef DO_TRIPLET_ROW
  }

  r00 = simd_sum(r00) * global_scale;
  r01 = simd_sum(r01) * global_scale;
  r02 = simd_sum(r02) * global_scale;
  r10 = simd_sum(r10) * global_scale;
  r11 = simd_sum(r11) * global_scale;
  r12 = simd_sum(r12) * global_scale;
  if (lane == 0) {
    if (row0 < n_rows) {
      if constexpr (ADD_RESIDUAL) {
        y[row0] += r00; y[n_rows + row0] += r01; y[2 * n_rows + row0] += r02;
      } else {
        y[row0] = r00; y[n_rows + row0] = r01; y[2 * n_rows + row0] = r02;
      }
    }
    if (row0 + 1 < n_rows) {
      if constexpr (ADD_RESIDUAL) {
        y[row0 + 1] += r10;
        y[n_rows + row0 + 1] += r11;
        y[2 * n_rows + row0 + 1] += r12;
      } else {
        y[row0 + 1] = r10;
        y[n_rows + row0 + 1] = r11;
        y[2 * n_rows + row0 + 1] = r12;
      }
    }
  }
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_triplet(
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],
  constant float &g [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_triplet_impl<false>(w, s, x, y, k, n, g, tg, sg, sl);
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_triplet_residual(
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],
  constant float &g [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_triplet_impl<true>(w, s, x, y, k, n, g, tg, sg, sl);
}

template <bool ADD_RESIDUAL>
static inline void nvfp4_matvec_mlx_scaled_triplet_r1_impl(
  device const uint *w_packed, device const uchar *w_scales,
  device const float *x, device float *y,
  constant int &k_dim, constant int &n_rows, constant float &global_scale,
  uint tg, uint simd_id, uint lane) {
  const int row = int(tg) * 2 + int(simd_id);
  if (row >= n_rows) return;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  float a0 = 0.0f, a1 = 0.0f, a2 = 0.0f;
  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int group = g_block + int(lane);
    if (group >= n_groups) continue;
    const int x_off = group * 16;
    device const float4 *x0 = (device const float4 *)(&x[x_off]);
    device const float4 *x1 = (device const float4 *)(&x[k_dim + x_off]);
    device const float4 *x2 = (device const float4 *)(&x[2 * k_dim + x_off]);
    const uint w0 = w_packed[row * u32s_per_row + group * 2];
    const uint w1 = w_packed[row * u32s_per_row + group * 2 + 1];
    const float s = float(e4m3_decode_half_triplet(
      uint(w_scales[row * n_groups + group])));
    const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
    const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
    const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
    const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
    const float4 v0 = float4(nvfp4_decode_half_triplet(b00 & 0xf),
      nvfp4_decode_half_triplet(b00 >> 4), nvfp4_decode_half_triplet(b01 & 0xf),
      nvfp4_decode_half_triplet(b01 >> 4));
    const float4 v1 = float4(nvfp4_decode_half_triplet(b02 & 0xf),
      nvfp4_decode_half_triplet(b02 >> 4), nvfp4_decode_half_triplet(b03 & 0xf),
      nvfp4_decode_half_triplet(b03 >> 4));
    const float4 v2 = float4(nvfp4_decode_half_triplet(b10 & 0xf),
      nvfp4_decode_half_triplet(b10 >> 4), nvfp4_decode_half_triplet(b11 & 0xf),
      nvfp4_decode_half_triplet(b11 >> 4));
    const float4 v3 = float4(nvfp4_decode_half_triplet(b12 & 0xf),
      nvfp4_decode_half_triplet(b12 >> 4), nvfp4_decode_half_triplet(b13 & 0xf),
      nvfp4_decode_half_triplet(b13 >> 4));
    a0 += s * (dot(v0, x0[0]) + dot(v1, x0[1]) + dot(v2, x0[2]) + dot(v3, x0[3]));
    a1 += s * (dot(v0, x1[0]) + dot(v1, x1[1]) + dot(v2, x1[2]) + dot(v3, x1[3]));
    a2 += s * (dot(v0, x2[0]) + dot(v1, x2[1]) + dot(v2, x2[2]) + dot(v3, x2[3]));
  }
  a0 = simd_sum(a0) * global_scale;
  a1 = simd_sum(a1) * global_scale;
  a2 = simd_sum(a2) * global_scale;
  if (lane == 0) {
    if constexpr (ADD_RESIDUAL) {
      y[row] += a0; y[n_rows + row] += a1; y[2 * n_rows + row] += a2;
    } else {
      y[row] = a0; y[n_rows + row] = a1; y[2 * n_rows + row] = a2;
    }
  }
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_triplet_r1(
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],
  constant float &g [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_triplet_r1_impl<false>(w, s, x, y, k, n, g, tg, sg, sl);
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_triplet_residual_r1(
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],
  constant float &g [[buffer(6)]],
  uint tg [[threadgroup_position_in_grid]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint sl [[thread_index_in_simdgroup]]) {
  nvfp4_matvec_mlx_scaled_triplet_r1_impl<true>(w, s, x, y, k, n, g, tg, sg, sl);
}
