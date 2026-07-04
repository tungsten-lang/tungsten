// Gather nvfp4 matvec for MoE batched-expert evaluation (MLX gather_qmm style).
//
// For each (k_idx, m) ∈ [0,K) × [0,N_ROWS) output:
//   y[k_idx, m] = Σ_g e4m3(scales[indices[k_idx], m, g]) ·
//                       Σ_j nvfp4(w[indices[k_idx], m, g, j]) · x[g*16 + j]
//
// Replaces 8 separate per-expert nvfp4_matvec_mlx dispatches with ONE.
//
// w_bytes and s_bytes are bound via metal_buffer_view (at runtime) to the
// per-tensor regions of the underlying whole-shard MTLBuffer. setBuffer:
// offset:atIndex: applies the offset at bind-time so the kernel sees the
// tensor starting at byte 0 of its bound buffer view.
//
// Byte-level u32 construction is still used inside the kernel: Metal
// setBuffer offset CAN be a non-u32-aligned absolute byte address (the
// safetensors data section starts mid-word), and `*(device const uint *)p`
// is undefined for misaligned p in MSL. Byte construction is alignment-safe.
//
// Buffer layout:
//   w_bytes    [N_EXPERTS * N_ROWS * K_DIM/8 * 4] u8 (per-tensor view)
//   s_bytes    [N_EXPERTS * N_ROWS * K_DIM/16]   u8 (per-tensor view)
//   indices    [K]            i32
//   x          [K_DIM]        f32
//   y          [K, N_ROWS]    f32
//   constants: k_dim, n_rows
//
// Dispatch: K * (N_ROWS / 8) TGs of 64 threads.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

// Misaligned-safe u32 read from byte stream.
static inline uint load_u32_le(device const uchar *p) {
  return (uint)p[0] | ((uint)p[1] << 8) | ((uint)p[2] << 16) | ((uint)p[3] << 24);
}

[[max_total_threads_per_threadgroup(64)]]
kernel void gather_nvfp4_matvec(
  device const uchar *__restrict__ w_base    [[buffer(0)]],
  device const uchar *__restrict__ s_base    [[buffer(1)]],
  device const int   *__restrict__ indices   [[buffer(2)]],
  device const float *__restrict__ x         [[buffer(3)]],
  device float       *__restrict__ y         [[buffer(4)]],
  constant int &k_dim   [[buffer(5)]],
  constant int &n_rows  [[buffer(6)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups     = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int tgs_per_k    = n_rows / 8;

  int tg       = int(__tg_id);
  int k_idx    = tg / tgs_per_k;
  int m_block  = tg % tgs_per_k;
  int expert   = indices[k_idx];
  int m_start  = m_block * 8 + int(__simd_id) * 4;
  int lane     = int(__simd_lane);

  // w_base / s_base are already bound at the tensor's start byte.
  // Index into the [N_EXPERTS, N_ROWS, K_DIM/{8,16}] tensor.
  ulong w_expert_byte_off = (ulong)(uint)expert * (ulong)(uint)n_rows * (ulong)((uint)u32s_per_row * 4u);
  ulong s_expert_byte_off = (ulong)(uint)expert * (ulong)(uint)n_rows * (ulong)(uint)n_groups;

  device const uchar *w_bytes = w_base + w_expert_byte_off;
  device const uchar *s_bytes = s_base + s_expert_byte_off;

  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) continue;

    int x_off = g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      device const uchar *w_row = w_bytes + (ulong)(uint)row * (ulong)((uint)u32s_per_row * 4u) + (ulong)((uint)g * 8u); \
      uint w0 = load_u32_le(w_row);                                       \
      uint w1 = load_u32_le(w_row + 4);                                   \
      uint sb = (uint)s_bytes[(ulong)(uint)row * (ulong)(uint)n_groups + (ulong)(uint)g]; \
      half scale_h = e4m3_decode_half(sb);                                \
      float scale = float(scale_h);                                       \
      uint b00 = w0 & 0xFF, b01 = (w0 >>  8) & 0xFF;                      \
      uint b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;              \
      uint b10 = w1 & 0xFF, b11 = (w1 >>  8) & 0xFF;                      \
      uint b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;              \
      float4 wv0 = float4(                                                \
        nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4),        \
        nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));       \
      float4 wv1 = float4(                                                \
        nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4),        \
        nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));       \
      float4 wv2 = float4(                                                \
        nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4),        \
        nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));       \
      float4 wv3 = float4(                                                \
        nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4),        \
        nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));       \
      float dp = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3); \
      accum += scale * dp;                                                \
    }

    DO_ROW(0, result0)
    DO_ROW(1, result1)
    DO_ROW(2, result2)
    DO_ROW(3, result3)
#undef DO_ROW
  }

  result0 = simd_sum(result0);
  result1 = simd_sum(result1);
  result2 = simd_sum(result2);
  result3 = simd_sum(result3);
  if (lane == 0) {
    int y_base = k_idx * n_rows + m_start;
    y[y_base + 0] = result0;
    y[y_base + 1] = result1;
    y[y_base + 2] = result2;
    y[y_base + 3] = result3;
  }
}
