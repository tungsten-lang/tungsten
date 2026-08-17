// GGML Q4_K matrix-vector multiply, consuming the packed GGUF block layout.
//
// A Q4_K super-block represents 256 weights in 144 bytes:
//   f16 d, f16 dmin, 12 packed scale/min bytes, 128 packed nibbles.
// Each SIMD lane reduces whole super-blocks; two SIMD groups compute eight
// output rows per threadgroup. Dequantization happens in registers while the
// dot product is accumulated, so weights are never expanded in device memory.
//
// Dispatch: ceil(n_rows / 8) threadgroups of 64 threads.

#include <metal_stdlib>
using namespace metal;

constant int Q4K_BLOCK_VALUES = 256;
constant int Q4K_BLOCK_BYTES = 144;

static inline uchar2 q4k_scale_min(device const uchar *packed, int group) {
  if (group < 4) {
    return uchar2(packed[group] & 63, packed[group + 4] & 63);
  }
  return uchar2(
    (packed[group + 4] & 0x0f) | ((packed[group - 4] >> 6) << 4),
    (packed[group + 4] >> 4) | ((packed[group] >> 6) << 4)
  );
}

static inline float4 q4k_low4(uint q) {
  return float4(
    float(q & 0x0f),
    float((q >> 8) & 0x0f),
    float((q >> 16) & 0x0f),
    float((q >> 24) & 0x0f)
  );
}

static inline float4 q4k_high4(uint q) {
  return float4(
    float((q >> 4) & 0x0f),
    float((q >> 12) & 0x0f),
    float((q >> 20) & 0x0f),
    float((q >> 28) & 0x0f)
  );
}

[[max_total_threads_per_threadgroup(64)]]
kernel void q4_k_matvec(
  device const uchar *__restrict__ packed [[buffer(0)]],
  device const float *__restrict__ x      [[buffer(1)]],
  device float       *__restrict__ y      [[buffer(2)]],
  constant int &k_dim                     [[buffer(3)]],
  constant int &n_rows                    [[buffer(4)]],
  uint tg_id     [[threadgroup_position_in_grid]],
  uint simd_id   [[simdgroup_index_in_threadgroup]],
  uint simd_lane [[thread_index_in_simdgroup]]) {
  const int blocks_per_row = k_dim / Q4K_BLOCK_VALUES;
  const int row0 = int(tg_id) * 8 + int(simd_id) * 4;
  const int lane = int(simd_lane);
  float result0 = 0.0f;
  float result1 = 0.0f;
  float result2 = 0.0f;
  float result3 = 0.0f;

  for (int block_wave = 0; block_wave < blocks_per_row; block_wave += 32) {
    const int block_index = block_wave + lane;
    if (block_index >= blocks_per_row) {
      continue;
    }
    const int x_block = block_index * Q4K_BLOCK_VALUES;

    // Four pairs of 32-value groups share the same 32 packed bytes: the
    // first group occupies low nibbles and the second the high nibbles.
    for (int pair = 0; pair < 4; ++pair) {
      const int group0 = pair * 2;
      const int group1 = group0 + 1;
      const int x0 = x_block + pair * 64;

      for (int chunk = 0; chunk < 8; ++chunk) {
        const float4 xv0 = *((device const float4 *)(x + x0 + chunk * 4));
        const float4 xv1 = *((device const float4 *)(x + x0 + 32 + chunk * 4));
        const float sx0 = xv0.x + xv0.y + xv0.z + xv0.w;
        const float sx1 = xv1.x + xv1.y + xv1.z + xv1.w;

#define Q4K_ACCUM_ROW(ROW_OFFSET, ACCUM)                                      \
        if (row0 + (ROW_OFFSET) < n_rows) {                                   \
          const int row = row0 + (ROW_OFFSET);                                \
          device const uchar *block = packed +                               \
            (row * blocks_per_row + block_index) * Q4K_BLOCK_BYTES;           \
          const float d = float(*((device const half *)(block + 0)));          \
          const float dmin = float(*((device const half *)(block + 2)));       \
          device const uchar *scale_bytes = block + 4;                        \
          const uchar2 sm0 = q4k_scale_min(scale_bytes, group0);              \
          const uchar2 sm1 = q4k_scale_min(scale_bytes, group1);              \
          device const uint *qwords = (device const uint *)(block + 16 +      \
            pair * 32);                                                       \
          const uint q = qwords[chunk];                                       \
          ACCUM += (d * float(sm0.x)) * dot(q4k_low4(q), xv0) -               \
                   (dmin * float(sm0.y)) * sx0 +                              \
                   (d * float(sm1.x)) * dot(q4k_high4(q), xv1) -              \
                   (dmin * float(sm1.y)) * sx1;                               \
        }

        Q4K_ACCUM_ROW(0, result0)
        Q4K_ACCUM_ROW(1, result1)
        Q4K_ACCUM_ROW(2, result2)
        Q4K_ACCUM_ROW(3, result3)
#undef Q4K_ACCUM_ROW
      }
    }
  }

  result0 = simd_sum(result0);
  result1 = simd_sum(result1);
  result2 = simd_sum(result2);
  result3 = simd_sum(result3);
  if (lane == 0) {
    if (row0 + 0 < n_rows) y[row0 + 0] = result0;
    if (row0 + 1 < n_rows) y[row0 + 1] = result1;
    if (row0 + 2 < n_rows) y[row0 + 2] = result2;
    if (row0 + 3 < n_rows) y[row0 + 3] = result3;
  }
}
