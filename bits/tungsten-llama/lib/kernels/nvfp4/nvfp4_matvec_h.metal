// nvfp4 matvec with half-precision accumulator. Halves register pressure
// on `partial`, possibly improving occupancy. Sums across simdgroup in
// half then promotes to float for the y-write.

#include <metal_stdlib>
using namespace metal;

constant half NVFP4_TABLE_H[16] = {
     0.0h,  0.5h,  1.0h,  1.5h,
     2.0h,  3.0h,  4.0h,  6.0h,
    -0.0h, -0.5h, -1.0h, -1.5h,
    -2.0h, -3.0h, -4.0h, -6.0h,
};

static inline half e4m3_decode_h(uint b) {
    uint s = (b >> 7) & 0x1;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    half sign = s ? -1.0h : 1.0h;
    if (e == 0) return sign * half(m) * (1.0h / 512.0h);
    if (e == 15 && m == 7) return 0.0h;
    half mantissa = 1.0h + half(m) * 0.125h;
    return sign * exp2(half(int(e) - 7)) * mantissa;
}

[[max_total_threads_per_threadgroup(32)]]
kernel void nvfp4_matvec_h(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const float *__restrict__ x        [[buffer(2)]],
  device float *__restrict__ y              [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  int n_groups = k_dim / 16;
  int u32s_per_row = k_dim / 8;

  half partial = 0.0h;
  int g = lane;
  while (g < n_groups) {
    uint w0 = w_packed[m * u32s_per_row + g * 2];
    uint w1 = w_packed[m * u32s_per_row + g * 2 + 1];
    half s = e4m3_decode_h(uint(w_scales[m * n_groups + g]));

    int x_off = g * 16;
    device const float4 *xp = (device const float4*)(&x[x_off]);
    half4 x0 = half4(xp[0]); half4 x1 = half4(xp[1]);
    half4 x2 = half4(xp[2]); half4 x3 = half4(xp[3]);

    uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF, b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
    half4 wv0 = half4(NVFP4_TABLE_H[b00 & 0xF], NVFP4_TABLE_H[b00 >> 4],
                      NVFP4_TABLE_H[b01 & 0xF], NVFP4_TABLE_H[b01 >> 4]);
    half4 wv1 = half4(NVFP4_TABLE_H[b02 & 0xF], NVFP4_TABLE_H[b02 >> 4],
                      NVFP4_TABLE_H[b03 & 0xF], NVFP4_TABLE_H[b03 >> 4]);
    uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF, b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;
    half4 wv2 = half4(NVFP4_TABLE_H[b10 & 0xF], NVFP4_TABLE_H[b10 >> 4],
                      NVFP4_TABLE_H[b11 & 0xF], NVFP4_TABLE_H[b11 >> 4]);
    half4 wv3 = half4(NVFP4_TABLE_H[b12 & 0xF], NVFP4_TABLE_H[b12 >> 4],
                      NVFP4_TABLE_H[b13 & 0xF], NVFP4_TABLE_H[b13 >> 4]);

    half block_acc = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3);
    partial += s * block_acc;
    g += 32;
  }

  half total = simd_sum(partial);
  if (lane == 0) {
    y[m] = float(total);
  }
}
