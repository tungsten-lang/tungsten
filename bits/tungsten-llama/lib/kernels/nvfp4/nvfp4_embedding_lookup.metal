// Dequantize ONE row of an nvfp4 embedding table into x_buf.
// Used at the start of each forward pass to materialize the token's
// embedding from the packed nvfp4 vocabulary.
//
// Layout matches nvfp4_matvec: w_packed and scales are row-major over
// vocab. Each row holds k_dim nvfp4 values = k_dim/8 uint32s = k_dim/16
// fp8 scales.
//
// Dispatch: n_groups (= k_dim/16) threads. Each writes 16 f32 outputs.

#include <metal_stdlib>
using namespace metal;

constant float NVFP4_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,
     2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f,
    -2.0f, -3.0f, -4.0f, -6.0f,
};

static inline float e4m3_decode(uint b) {
    b = b & 0x7F;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    if (e == 0) return float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7) return 0.0f;
    float mantissa = 1.0f + float(m) * 0.125f;
    return exp2(float(int(e) - 7)) * mantissa;
}

kernel void nvfp4_embedding_lookup(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ scales   [[buffer(1)]],
  device float       *__restrict__ out      [[buffer(2)]],
  constant int &token_id [[buffer(3)]],
  constant int &k_dim    [[buffer(4)]],
  uint tid [[thread_position_in_grid]]
) {
  int n_groups = k_dim / 16;
  if (int(tid) >= n_groups) return;

  int u32s_per_row = k_dim / 8;
  int row_u32_off = token_id * u32s_per_row + int(tid) * 2;
  int row_scl_off = token_id * n_groups + int(tid);

  uint w0 = w_packed[row_u32_off];
  uint w1 = w_packed[row_u32_off + 1];
  float s = e4m3_decode(uint(scales[row_scl_off]));

  int out_base = int(tid) * 16;
  for (int i = 0; i < 4; i++) {
    uint b = (w0 >> (i * 8)) & 0xFF;
    out[out_base + i * 2 + 0] = NVFP4_TABLE[b & 0xF]      * s;
    out[out_base + i * 2 + 1] = NVFP4_TABLE[(b >> 4) & 0xF] * s;
  }
  for (int i = 0; i < 4; i++) {
    uint b = (w1 >> (i * 8)) & 0xFF;
    out[out_base + 8 + i * 2 + 0] = NVFP4_TABLE[b & 0xF]      * s;
    out[out_base + 8 + i * 2 + 1] = NVFP4_TABLE[(b >> 4) & 0xF] * s;
  }
}
