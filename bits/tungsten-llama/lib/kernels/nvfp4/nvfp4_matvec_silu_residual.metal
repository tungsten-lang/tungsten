// nvfp4 matvec that reads x = silu(gate[i]) * up[i] on the fly and adds
// into y. Replaces (silu_mul → barrier → down_proj_residual) at decode.
// Single-token variant. k_dim is the FFN intermediate width.

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
kernel void nvfp4_matvec_silu_residual(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const float *__restrict__ gate     [[buffer(2)]],
  device const float *__restrict__ up       [[buffer(3)]],
  device float       *__restrict__ y        [[buffer(4)]],
  constant int &k_dim [[buffer(5)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  int n_groups = k_dim / 16;
  int u32s_per_row = k_dim / 8;

  float partial = 0.0f;
  int g = lane;
  while (g < n_groups) {
    uint w0 = w_packed[m * u32s_per_row + g * 2];
    uint w1 = w_packed[m * u32s_per_row + g * 2 + 1];
    float s = e4m3_decode(uint(w_scales[m * n_groups + g]));

    // Compute h = silu(gate) * up for these 16 elements on the fly
    int x_off = g * 16;
    float h[16];
    for (int j = 0; j < 16; j++) {
      float gv = gate[x_off + j];
      float uv = up[x_off + j];
      float sig = 1.0f / (1.0f + exp(-gv));
      h[j] = (gv * sig) * uv;
    }

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

    float4 h0 = float4(h[0], h[1], h[2], h[3]);
    float4 h1 = float4(h[4], h[5], h[6], h[7]);
    float4 h2 = float4(h[8], h[9], h[10], h[11]);
    float4 h3 = float4(h[12], h[13], h[14], h[15]);

    float block_acc = dot(wv0, h0) + dot(wv1, h1) + dot(wv2, h2) + dot(wv3, h3);
    partial += s * block_acc;
    g += 32;
  }

  float total = simd_sum(partial);
  if (lane == 0) y[m] = y[m] + total;
}
