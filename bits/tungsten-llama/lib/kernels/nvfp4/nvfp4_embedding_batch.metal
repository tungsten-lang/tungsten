// Batched embedding lookup. Dispatch BATCH * (k_dim/16) threads.
// Each thread writes 16 f32 outputs at out[token * k_dim + group*16 ..].
// Token IDs in token_ids buffer.

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

kernel void nvfp4_embedding_batch(
  device const uint  *__restrict__ w_packed  [[buffer(0)]],
  device const uchar *__restrict__ scales    [[buffer(1)]],
  device float       *__restrict__ out       [[buffer(2)]],
  device const int   *__restrict__ token_ids [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  constant int &batch [[buffer(5)]],
  uint tid [[thread_position_in_grid]]
) {
  int n_groups = k_dim / 16;
  int total = batch * n_groups;
  if (int(tid) >= total) return;

  int t = int(tid) / n_groups;
  int g = int(tid) - t * n_groups;
  int token_id = token_ids[t];

  int u32s_per_row = k_dim / 8;
  int row_u32_off = token_id * u32s_per_row + g * 2;
  int row_scl_off = token_id * n_groups + g;

  uint w0 = w_packed[row_u32_off];
  uint w1 = w_packed[row_u32_off + 1];
  float s = e4m3_decode(uint(scales[row_scl_off]));

  int out_base = t * k_dim + g * 16;
  for (int i = 0; i < 4; i++) {
    uint b = (w0 >> (i * 8)) & 0xFF;
    out[out_base + i * 2 + 0] = NVFP4_TABLE[b & 0xF]        * s;
    out[out_base + i * 2 + 1] = NVFP4_TABLE[(b >> 4) & 0xF] * s;
  }
  for (int i = 0; i < 4; i++) {
    uint b = (w1 >> (i * 8)) & 0xFF;
    out[out_base + 8 + i * 2 + 0] = NVFP4_TABLE[b & 0xF]        * s;
    out[out_base + 8 + i * 2 + 1] = NVFP4_TABLE[(b >> 4) & 0xF] * s;
  }
}
