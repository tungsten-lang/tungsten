// nvfp4 batched matvec that writes directly into a cache row instead of
// a contiguous y buffer. Replaces (v_proj batched + kv_write) chain.
// Cache layout: cache[token * row_size + m] for output row m at token.

#include <metal_stdlib>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

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
kernel void nvfp4_matvec_batch_to_cache_fc(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device const float *__restrict__ x        [[buffer(2)]],
  device float       *__restrict__ cache    [[buffer(3)]],
  constant int &row_size [[buffer(4)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg) / N_ROWS_FC;
  int m = int(tg) - token * N_ROWS_FC;
  if (token >= BATCH_FC) return;

  const int n_groups = K_DIM_FC / 16;
  const int u32s_per_row = K_DIM_FC / 8;
  int x_base = token * K_DIM_FC;

  float partial = 0.0f;
  for (int g = int(lane); g < n_groups; g += 32) {
    uint w0 = w_packed[m * u32s_per_row + g * 2];
    uint w1 = w_packed[m * u32s_per_row + g * 2 + 1];
    float s = e4m3_decode(uint(w_scales[m * n_groups + g]));

    int x_off = x_base + g * 16;
    device const float4 *xp = (device const float4*)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

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

    float block_acc = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3);
    partial += s * block_acc;
  }

  float total = simd_sum(partial);
  if (lane == 0) cache[token * row_size + m] = total;
}
