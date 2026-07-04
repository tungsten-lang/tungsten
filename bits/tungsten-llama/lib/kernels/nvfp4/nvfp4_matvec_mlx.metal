// nvfp4 matvec, MLX-style. 8 output rows per TG (2 simdgroups × 4 rows).
// Each simdgroup loads its 16-element x register tile ONCE per K block and
// reuses it across 4 output rows. Bit-cast fp4 + E4M3 decode (no LUT,
// no branches, no transcendentals).
//
// Dispatch: ceil(N_ROWS / 8) TGs of 64 threads (2 simdgroups).
// K must be a multiple of 16 (group_size).

#include <metal_stdlib>
using namespace metal;

// Decode one nvfp4 nibble to half. Magnitude table {0,0.5,1,1.5,2,3,4,6}
// is encoded as (m << 9) reinterpreted as half, scaled by 2^14. Sign in bit 3.
static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

// Decode one E4M3 fp8 scale to half. Place 7 bits of (exp:4 | mantissa:3)
// into bits 7..13 of a half, scale by 2^8. Sign bit ignored (nvfp4 scales >= 0).
static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx(
  device const uint  *__restrict__ w_packed [[buffer(0)]],   // [N × K/8] u32, low nibble first
  device const uchar *__restrict__ w_scales [[buffer(1)]],   // [N × K/16] E4M3
  device const float *__restrict__ x        [[buffer(2)]],   // [K] f32
  device float       *__restrict__ y        [[buffer(3)]],   // [N] f32
  constant int &k_dim [[buffer(4)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;

  // Each TG produces 8 contiguous output rows; each simdgroup handles 4 rows.
  int m_start = int(__tg_id) * 8 + int(__simd_id) * 4;
  int lane = int(__simd_lane);

  // Per-lane accumulators for the 4 rows this simdgroup owns.
  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  // Loop K in 512-element blocks (one block = one full simdgroup turn).
  // Lane `lane` owns groups (g_start + lane) within each block.
  // values_per_thread = 16, block_size = 16 * 32 = 512.
  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) {
      // Tail (k_dim not a multiple of 512). All lanes still tick the loop.
      continue;
    }

    // Load 16 floats of x for this lane's K range, once per K block.
    int x_off = g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

    // For each of the 4 rows owned by this simdgroup, compute the partial
    // dot product over this lane's 16 weight values.
    // Unrolled by hand to keep accumulators in registers.
#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      uint w0 = w_packed[row * u32s_per_row + g * 2];                     \
      uint w1 = w_packed[row * u32s_per_row + g * 2 + 1];                 \
      half scale_h = e4m3_decode_half(uint(w_scales[row * n_groups + g]));\
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

  // Reduce each row across lanes; lane 0 writes the 4 outputs.
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
