// Layout experiment for NVFP4 QMV/QMM.
//
// The checkpoint is output-row-major: [row][K/16 groups]. The repack kernels
// transpose groups and rows to [group][row], after which one GPU thread owns
// an output row. At each K group, adjacent threads read adjacent weights while
// sharing the same activation group through cache. This removes simdgroup
// reductions at the cost of a serial K loop per output row.

#include <metal_stdlib>
using namespace metal;

kernel void nvfp4_repack_group_major_weights(
  device const uint2 *__restrict__ src [[buffer(0)]],
  device uint2       *__restrict__ dst [[buffer(1)]],
  constant int &n_rows [[buffer(2)]],
  constant int &n_groups [[buffer(3)]],
  uint index [[thread_position_in_grid]]) {
  const uint total = uint(n_rows * n_groups);
  if (index >= total) return;
  const int row = int(index) / n_groups;
  const int group = int(index) - row * n_groups;
  dst[group * n_rows + row] = src[row * n_groups + group];
}

kernel void nvfp4_repack_group_major_scales(
  device const uchar *__restrict__ src [[buffer(0)]],
  device uchar       *__restrict__ dst [[buffer(1)]],
  constant int &n_rows [[buffer(2)]],
  constant int &n_groups [[buffer(3)]],
  uint index [[thread_position_in_grid]]) {
  const uint total = uint(n_rows * n_groups);
  if (index >= total) return;
  const int row = int(index) / n_groups;
  const int group = int(index) - row * n_groups;
  dst[group * n_rows + row] = src[row * n_groups + group];
}

static inline half nvfp4_decode_half_colmajor(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_colmajor(uint byte) {
  return as_type<half>(ushort((byte & 127) << 7)) * 256.0h;
}

kernel void nvfp4_matvec_mlx_scaled_colmajor(
  device const uint2 *__restrict__ w_group_major [[buffer(0)]],
  device const uchar *__restrict__ s_group_major [[buffer(1)]],
  device const float *__restrict__ x [[buffer(2)]],
  device float *__restrict__ y [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  constant int &n_rows [[buffer(5)]],
  constant int &batch [[buffer(6)]],
  constant float &global_scale [[buffer(7)]],
  uint row [[thread_position_in_grid]]) {
  if (row >= uint(n_rows)) return;
  const int n_groups = k_dim / 16;
  float a0 = 0.0f, a1 = 0.0f, a2 = 0.0f, a3 = 0.0f, a4 = 0.0f;

  for (int group = 0; group < n_groups; ++group) {
    const uint2 packed = w_group_major[group * n_rows + int(row)];
    const float scale = float(e4m3_decode_half_colmajor(
      uint(s_group_major[group * n_rows + int(row)])));
    const uint w0 = packed.x, w1 = packed.y;
    const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
    const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
    const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
    const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
    const float4 v0 = float4(nvfp4_decode_half_colmajor(b00 & 0xf),
      nvfp4_decode_half_colmajor(b00 >> 4),
      nvfp4_decode_half_colmajor(b01 & 0xf),
      nvfp4_decode_half_colmajor(b01 >> 4));
    const float4 v1 = float4(nvfp4_decode_half_colmajor(b02 & 0xf),
      nvfp4_decode_half_colmajor(b02 >> 4),
      nvfp4_decode_half_colmajor(b03 & 0xf),
      nvfp4_decode_half_colmajor(b03 >> 4));
    const float4 v2 = float4(nvfp4_decode_half_colmajor(b10 & 0xf),
      nvfp4_decode_half_colmajor(b10 >> 4),
      nvfp4_decode_half_colmajor(b11 & 0xf),
      nvfp4_decode_half_colmajor(b11 >> 4));
    const float4 v3 = float4(nvfp4_decode_half_colmajor(b12 & 0xf),
      nvfp4_decode_half_colmajor(b12 >> 4),
      nvfp4_decode_half_colmajor(b13 & 0xf),
      nvfp4_decode_half_colmajor(b13 >> 4));

#define COL_DOT(B)                                                           \
    (dot(v0, ((device const float4 *)(&x[(B) * k_dim + group * 16]))[0]) +  \
     dot(v1, ((device const float4 *)(&x[(B) * k_dim + group * 16]))[1]) +  \
     dot(v2, ((device const float4 *)(&x[(B) * k_dim + group * 16]))[2]) +  \
     dot(v3, ((device const float4 *)(&x[(B) * k_dim + group * 16]))[3]))
    a0 += scale * COL_DOT(0);
    if (batch >= 2) a1 += scale * COL_DOT(1);
    if (batch >= 3) a2 += scale * COL_DOT(2);
    if (batch >= 4) a3 += scale * COL_DOT(3);
    if (batch >= 5) a4 += scale * COL_DOT(4);
#undef COL_DOT
  }

  y[row] = a0 * global_scale;
  if (batch >= 2) y[n_rows + row] = a1 * global_scale;
  if (batch >= 3) y[2 * n_rows + row] = a2 * global_scale;
  if (batch >= 4) y[3 * n_rows + row] = a3 * global_scale;
  if (batch >= 5) y[4 * n_rows + row] = a4 * global_scale;
}
