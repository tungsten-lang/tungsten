// One-shot dequant of an nvfp4-packed weight matrix into a f16 buffer
// at load time. After this runs, matmul kernels can read weights as
// half directly via simdgroup_load.
//
// Output layout: row-major [n_rows × k_dim] half values, scale already
// applied (each weight = NVFP4_TABLE[nibble] * E4M3_decode(scale)).
//
// Dispatch n_rows * (k_dim / 16) threads — one per nvfp4 group.

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

kernel void nvfp4_dequant_full(
  device const uint  *__restrict__ w_packed [[buffer(0)]],
  device const uchar *__restrict__ w_scales [[buffer(1)]],
  device half        *__restrict__ w_f16    [[buffer(2)]],
  constant int &k_dim  [[buffer(3)]],
  constant int &n_rows [[buffer(4)]],
  uint tid [[thread_position_in_grid]]
) {
  int n_groups = k_dim / 16;
  int total = n_rows * n_groups;
  if (int(tid) >= total) return;

  int row = int(tid) / n_groups;
  int g = int(tid) - row * n_groups;
  int u32s_per_row = k_dim / 8;

  uint w0 = w_packed[row * u32s_per_row + g * 2];
  uint w1 = w_packed[row * u32s_per_row + g * 2 + 1];
  float s = e4m3_decode(uint(w_scales[row * n_groups + g]));

  int out_base = row * k_dim + g * 16;
  for (int i = 0; i < 4; i++) {
    uint b = (w0 >> (i * 8)) & 0xFF;
    w_f16[out_base + i * 2 + 0] = half(NVFP4_TABLE[b & 0xF]        * s);
    w_f16[out_base + i * 2 + 1] = half(NVFP4_TABLE[(b >> 4) & 0xF] * s);
  }
  for (int i = 0; i < 4; i++) {
    uint b = (w1 >> (i * 8)) & 0xFF;
    w_f16[out_base + 8 + i * 2 + 0] = half(NVFP4_TABLE[b & 0xF]        * s);
    w_f16[out_base + 8 + i * 2 + 1] = half(NVFP4_TABLE[(b >> 4) & 0xF] * s);
  }
}
