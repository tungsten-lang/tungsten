// nvfp4 matvec v5: 2 groups per loop iter (32 weights, 16 bytes via uint4 read).
// Halves loop iterations vs v1; better instruction-level parallelism.
// Same dispatch shape as v1: 1 TG per output row, 32 lanes.

#include <metal_stdlib>
using namespace metal;

constant float NVFP4_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,
     2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f,
    -2.0f, -3.0f, -4.0f, -6.0f,
};

static inline float e4m3_decode(uint b) {
    uint s = (b >> 7) & 0x1;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    float sign = s ? -1.0f : 1.0f;
    if (e == 0) return sign * float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7) return 0.0f;
    float mantissa = 1.0f + float(m) * 0.125f;
    return sign * exp2(float(int(e) - 7)) * mantissa;
}

[[max_total_threads_per_threadgroup(32)]]
kernel void nvfp4_matvec_v5(
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

  float partial = 0.0f;
  int g = lane * 2;       // each lane processes group pairs (g, g+1)
  int stride = 64;        // 32 lanes × 2 groups
  while (g < n_groups) {
    // Read 4 uints (32 weight nibbles = 2 groups)
    uint4 ww = ((device const uint4*)&w_packed[m * u32s_per_row + g * 2])[0];
    uint w0 = ww.x, w1 = ww.y, w2 = ww.z, w3 = ww.w;
    float s0 = e4m3_decode(uint(w_scales[m * n_groups + g]));
    float s1 = e4m3_decode(uint(w_scales[m * n_groups + g + 1]));

    // 32 floats of x: 8 float4s
    int x_off = g * 16;
    device const float4 *xp = (device const float4*)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];
    float4 x4 = xp[4]; float4 x5 = xp[5];
    float4 x6 = xp[6]; float4 x7 = xp[7];

    // Group 0: w0, w1
    uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF, b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
    float4 wv0 = float4(NVFP4_TABLE[b00 & 0xF], NVFP4_TABLE[b00 >> 4],
                        NVFP4_TABLE[b01 & 0xF], NVFP4_TABLE[b01 >> 4]);
    float4 wv1 = float4(NVFP4_TABLE[b02 & 0xF], NVFP4_TABLE[b02 >> 4],
                        NVFP4_TABLE[b03 & 0xF], NVFP4_TABLE[b03 >> 4]);
    uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF, b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;
    float4 wv2 = float4(NVFP4_TABLE[b10 & 0xF], NVFP4_TABLE[b10 >> 4],
                        NVFP4_TABLE[b11 & 0xF], NVFP4_TABLE[b11 >> 4]);
    float4 wv3 = float4(NVFP4_TABLE[b12 & 0xF], NVFP4_TABLE[b12 >> 4],
                        NVFP4_TABLE[b13 & 0xF], NVFP4_TABLE[b13 >> 4]);
    float acc0 = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3);

    // Group 1: w2, w3
    uint c00 = w2 & 0xFF, c01 = (w2 >> 8) & 0xFF, c02 = (w2 >> 16) & 0xFF, c03 = (w2 >> 24) & 0xFF;
    float4 wv4 = float4(NVFP4_TABLE[c00 & 0xF], NVFP4_TABLE[c00 >> 4],
                        NVFP4_TABLE[c01 & 0xF], NVFP4_TABLE[c01 >> 4]);
    float4 wv5 = float4(NVFP4_TABLE[c02 & 0xF], NVFP4_TABLE[c02 >> 4],
                        NVFP4_TABLE[c03 & 0xF], NVFP4_TABLE[c03 >> 4]);
    uint c10 = w3 & 0xFF, c11 = (w3 >> 8) & 0xFF, c12 = (w3 >> 16) & 0xFF, c13 = (w3 >> 24) & 0xFF;
    float4 wv6 = float4(NVFP4_TABLE[c10 & 0xF], NVFP4_TABLE[c10 >> 4],
                        NVFP4_TABLE[c11 & 0xF], NVFP4_TABLE[c11 >> 4]);
    float4 wv7 = float4(NVFP4_TABLE[c12 & 0xF], NVFP4_TABLE[c12 >> 4],
                        NVFP4_TABLE[c13 & 0xF], NVFP4_TABLE[c13 >> 4]);
    float acc1 = dot(wv4, x4) + dot(wv5, x5) + dot(wv6, x6) + dot(wv7, x7);

    partial += s0 * acc0 + s1 * acc1;
    g += stride;
  }

  float total = simd_sum(partial);
  if (lane == 0) {
    y[m] = total;
  }
}
