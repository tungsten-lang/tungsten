// MLX-style fast NVFP4 QMV for group_size=16, bits=4, r=2.
//
// Each lane consumes two packed uint32 words (16 weights / one scale group)
// at a time. The packed qdot mirrors MLX's fp_qmv_fast path: view the eight
// packed bytes as four uint16 values and accumulate their four nibbles
// directly, without first materializing dequantized weight vectors.
//
// Dispatch: N_ROWS / 8 TGs of 64 threads. K must be a multiple of 512 and
// N_ROWS must be a multiple of 8.

#include <metal_stdlib>
using namespace metal;

static inline float nvfp4_decode_r_2(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return float((nibble & 8) ? -mag : mag);
}

static inline float e4m3_decode_r_2(uint byte) {
  return float(as_type<half>(ushort((byte & 127) << 7)) * 256.0h);
}

static inline float nvfp4_packed_qdot_r_2(
  device const ushort *__restrict__ packed,
  thread const float *__restrict__ activation
) {
  float accum = 0.0f;
#pragma unroll
  for (int i = 0; i < 4; ++i) {
    const uint word = uint(packed[i]);
    accum += activation[4 * i + 0] * nvfp4_decode_r_2(word);
    accum += activation[4 * i + 1] * nvfp4_decode_r_2(word >> 4);
    accum += activation[4 * i + 2] * nvfp4_decode_r_2(word >> 8);
    accum += activation[4 * i + 3] * nvfp4_decode_r_2(word >> 12);
  }
  return accum;
}

[[max_total_threads_per_threadgroup(64)]]
kernel void nvfp4_matvec_mlx_scaled_r_2(
  device const uint  *__restrict__ w_packed   [[buffer(0)]],
  device const uchar *__restrict__ w_scales   [[buffer(1)]],
  device const float *__restrict__ x          [[buffer(2)]],
  device float       *__restrict__ y          [[buffer(3)]],
  constant int       &k_dim                   [[buffer(4)]],
  constant float     &global_scale            [[buffer(5)]],
  uint tg_id       [[threadgroup_position_in_grid]],
  uint simd_id     [[simdgroup_index_in_threadgroup]],
  uint simd_lane   [[thread_index_in_simdgroup]]
) {
  constexpr int packs_per_lane = 2;
  constexpr int values_per_lane = 16;
  constexpr int values_per_simdgroup = values_per_lane * 32;
  constexpr int rows_per_simdgroup = 4;
  constexpr int simdgroups_per_threadgroup = 2;

  const int row0 = int(tg_id) *
      (rows_per_simdgroup * simdgroups_per_threadgroup) +
      int(simd_id) * rows_per_simdgroup;
  const int u32_per_row = k_dim / 8;
  const int scales_per_row = k_dim / 16;
  const int lane = int(simd_lane);

  device const uint *weights =
      w_packed + row0 * u32_per_row + lane * packs_per_lane;
  device const uchar *scales =
      w_scales + row0 * scales_per_row + lane;
  device const float *activation = x + lane * values_per_lane;

  float x_lane[values_per_lane];
  float result[rows_per_simdgroup] = {0.0f};

  for (int k = 0; k < k_dim; k += values_per_simdgroup) {
#pragma unroll
    for (int i = 0; i < values_per_lane; ++i) {
      x_lane[i] = activation[i];
    }

#pragma unroll
    for (int row = 0; row < rows_per_simdgroup; ++row) {
      device const ushort *packed =
          reinterpret_cast<device const ushort *>(weights + row * u32_per_row);
      const float scale =
          e4m3_decode_r_2(uint(scales[row * scales_per_row]));
      result[row] += scale * nvfp4_packed_qdot_r_2(packed, x_lane);
    }

    weights += values_per_simdgroup / 8;
    scales += values_per_simdgroup / 16;
    activation += values_per_simdgroup;
  }

#pragma unroll
  for (int row = 0; row < rows_per_simdgroup; ++row) {
    result[row] = simd_sum(result[row]) * global_scale;
    if (lane == 0) {
      y[row0 + row] = result[row];
    }
  }
}
