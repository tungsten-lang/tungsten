// NVFP4 dequantize — converts packed 4-bit E2M1 weights with E4M3
// fp8 group scales back to f32.
//
// Layout (per MLX convention):
//   weights: uint32[N * K/8]       — each uint32 packs 8 nvfp4 nibbles
//                                    (low nibble first within each byte)
//   scales:  uint8[N * K/16]       — one E4M3 fp8 scale per 16 weights
//   output:  float[N * K]          — dequantized weights
//
// NVFP4 (E2M1, 4-bit) value table, indexed by nibble:
//   0x0 =  0.0    0x1 =  0.5    0x2 =  1.0    0x3 =  1.5
//   0x4 =  2.0    0x5 =  3.0    0x6 =  4.0    0x7 =  6.0
//   0x8 = -0.0    0x9 = -0.5    0xA = -1.0    0xB = -1.5
//   0xC = -2.0    0xD = -3.0    0xE = -4.0    0xF = -6.0
//
// E4M3 fp8 scale decode:
//   sign bit [7], exponent bits [6:3] (bias 7), mantissa bits [2:0]
//   Normal:    value = (-1)^s * 2^(e-7) * (1 + m/8)
//   Subnormal: value = (-1)^s * 2^(-6) * (m/8)     (when e == 0)
//   Special:   e == 15 && m == 7 — NaN (OCP spec).

#include <metal_stdlib>
using namespace metal;

// Decode one nvfp4 nibble (0..15) to a float.
static inline float nvfp4_decode(uint nib) {
    const float table[16] = {
         0.0f,  0.5f,  1.0f,  1.5f,
         2.0f,  3.0f,  4.0f,  6.0f,
        -0.0f, -0.5f, -1.0f, -1.5f,
        -2.0f, -3.0f, -4.0f, -6.0f,
    };
    return table[nib & 0xF];
}

// Decode one E4M3 fp8 byte to a float.
static inline float e4m3_decode(uint b) {
    uint s = (b >> 7) & 0x1;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    float sign = s ? -1.0f : 1.0f;
    if (e == 0) {
        // subnormal:  s * 2^-6 * (m/8)
        return sign * float(m) * (1.0f / 512.0f);
    }
    if (e == 15 && m == 7) return 0.0f;  // NaN sentinel → 0 for safety
    // normal:  s * 2^(e-7) * (1 + m/8)
    float mantissa = 1.0f + float(m) * 0.125f;
    float exp_scale = exp2(float(int(e) - 7));
    return sign * exp_scale * mantissa;
}

kernel void nvfp4_dequant(
  device const uint *__restrict__ w_packed [[buffer(0)]],  // uint32[n * k/8]
  device const uchar *__restrict__ scales  [[buffer(1)]],  // uint8[n * k/16]
  device float *__restrict__ out           [[buffer(2)]],  // float[n * k]
  constant int &n [[buffer(3)]],   // output rows (dim 0)
  constant int &k [[buffer(4)]],   // input cols (dim 1, dequantized)
  uint __tid [[thread_position_in_grid]]
) {
  // One thread per group of 16 output values = one scale's worth.
  int total_groups = n * (k / 16);
  if (int(__tid) >= total_groups) return;

  int row = int(__tid) / (k / 16);
  int grp = int(__tid) % (k / 16);     // which 16-element group in this row
  int col_base = grp * 16;

  // Group spans 2 uint32s (2 × 8 nibbles = 16 nibbles)
  int uint32_idx = row * (k / 8) + grp * 2;
  uint w0 = w_packed[uint32_idx];
  uint w1 = w_packed[uint32_idx + 1];

  // Scale byte for this group
  uint sbyte = scales[row * (k / 16) + grp];
  float s = e4m3_decode(sbyte);

  // Write 16 dequantized values. Nibble order is low-nibble-first
  // within each byte: byte b of w0 → nibbles (b<<1), (b<<1)+1 = low, high.
  int out_off = row * k + col_base;
  for (int i = 0; i < 4; i++) {
    uint byte = (w0 >> (i * 8)) & 0xFF;
    out[out_off + i * 2 + 0] = nvfp4_decode(byte & 0xF)      * s;
    out[out_off + i * 2 + 1] = nvfp4_decode((byte >> 4) & 0xF) * s;
  }
  for (int i = 0; i < 4; i++) {
    uint byte = (w1 >> (i * 8)) & 0xFF;
    out[out_off + 8 + i * 2 + 0] = nvfp4_decode(byte & 0xF)      * s;
    out[out_off + 8 + i * 2 + 1] = nvfp4_decode((byte >> 4) & 0xF) * s;
  }
}
