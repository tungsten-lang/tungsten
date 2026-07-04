// Fused NVFP4 matvec: y = W·x where W is nvfp4-quantized.
//
// Layout:
//   w_packed: uint32[n_rows × k/8]   (8 nvfp4 nibbles per uint32)
//   w_scales: uint8[n_rows  × k/16]  (1 E4M3 fp8 scale per 16 weights)
//   x:        float[k]
//   y:        float[n_rows]
//
// Dispatch: n_rows threadgroups × 32 lanes.

#include <metal_stdlib>
using namespace metal;

// nvfp4 (E2M1) value table
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
    if (e == 0) {
        return sign * float(m) * (1.0f / 512.0f);
    }
    if (e == 15 && m == 7) return 0.0f;
    float mantissa = 1.0f + float(m) * 0.125f;
    float exp_scale = exp2(float(int(e) - 7));
    return sign * exp_scale * mantissa;
}

[[max_total_threads_per_threadgroup(32)]]
kernel void nvfp4_matvec(
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
  int n_groups = k_dim / 16;            // groups per row (each = 16 weights, 1 scale)
  int u32s_per_row = k_dim / 8;         // uint32s per row

  float partial = 0.0f;
  int g = lane;
  while (g < n_groups) {
    // Group g uses 2 uint32s + 1 scale byte
    uint w0 = w_packed[m * u32s_per_row + g * 2];
    uint w1 = w_packed[m * u32s_per_row + g * 2 + 1];
    float s = e4m3_decode(uint(w_scales[m * n_groups + g]));

    int x_off = g * 16;
    // Activation reads as 4 × float4 = 16 floats
    device const float4 *xp = (device const float4*)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

    // Decode 16 nvfp4 weights from (w0, w1), accumulate into block_acc
    // Low-nibble-first within each byte. byte b → nibbles (b<<1), (b<<1)+1.
    float block_acc = 0.0f;
    // w0: bytes 0-3 → 8 weights → x0 (4) + x1 (4)
    uint b00 = w0 & 0xFF;
    uint b01 = (w0 >> 8) & 0xFF;
    uint b02 = (w0 >> 16) & 0xFF;
    uint b03 = (w0 >> 24) & 0xFF;
    float4 wv0 = float4(NVFP4_TABLE[b00 & 0xF], NVFP4_TABLE[b00 >> 4],
                        NVFP4_TABLE[b01 & 0xF], NVFP4_TABLE[b01 >> 4]);
    float4 wv1 = float4(NVFP4_TABLE[b02 & 0xF], NVFP4_TABLE[b02 >> 4],
                        NVFP4_TABLE[b03 & 0xF], NVFP4_TABLE[b03 >> 4]);
    block_acc += dot(wv0, x0);
    block_acc += dot(wv1, x1);

    uint b10 = w1 & 0xFF;
    uint b11 = (w1 >> 8) & 0xFF;
    uint b12 = (w1 >> 16) & 0xFF;
    uint b13 = (w1 >> 24) & 0xFF;
    float4 wv2 = float4(NVFP4_TABLE[b10 & 0xF], NVFP4_TABLE[b10 >> 4],
                        NVFP4_TABLE[b11 & 0xF], NVFP4_TABLE[b11 >> 4]);
    float4 wv3 = float4(NVFP4_TABLE[b12 & 0xF], NVFP4_TABLE[b12 >> 4],
                        NVFP4_TABLE[b13 & 0xF], NVFP4_TABLE[b13 >> 4]);
    block_acc += dot(wv2, x2);
    block_acc += dot(wv3, x3);

    partial += s * block_acc;
    g += 32;
  }

  float total = simd_sum(partial);
  if (lane == 0) {
    y[m] = total;
  }
}
