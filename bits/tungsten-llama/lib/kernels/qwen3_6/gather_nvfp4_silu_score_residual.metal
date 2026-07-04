// Fused gather + nvfp4 down-projection + silu_mul + score-weighted residual.
// Replaces (silu_mul + per-expert down matvec + per-expert wadd) for ALL K
// experts with ONE dispatch.
//
// y[m] += Σ_{k=0..K-1} scores[k] · Σ_g e4m3(s[indices[k], m, g])
//                                     · Σ_j nvfp4(w[indices[k], m, g, j])
//                                       · silu(gate[k, g*16+j]) · up[k, g*16+j]
//
// Takes shard-base + per-tensor byte offsets (see gather_nvfp4_matvec for
// why — safetensors slices are non-page-aligned so we wrap the whole shard
// and offset inside the kernel).

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

static inline uint load_u32_le(device const uchar *p) {
  return (uint)p[0] | ((uint)p[1] << 8) | ((uint)p[2] << 16) | ((uint)p[3] << 24);
}

[[max_total_threads_per_threadgroup(32)]]
kernel void gather_nvfp4_silu_score_residual(
  device const uchar *__restrict__ w_base   [[buffer(0)]],
  device const uchar *__restrict__ s_base   [[buffer(1)]],
  device const float *__restrict__ gate     [[buffer(2)]],
  device const float *__restrict__ up       [[buffer(3)]],
  device const int   *__restrict__ indices  [[buffer(4)]],
  device const float *__restrict__ scores   [[buffer(5)]],
  device float       *__restrict__ y        [[buffer(6)]],
  constant int &k_dim   [[buffer(7)]],
  constant int &n_out   [[buffer(8)]],
  constant int &top_k   [[buffer(9)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups     = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int total_inner  = top_k * n_groups;

  int m    = int(__tg_id);
  int lane = int(__simd_lane);

  // w_base / s_base bound at tensor start by metal_buffer_view; just index.
  float partial = 0.0f;

  for (int idx = lane; idx < total_inner; idx += 32) {
    int k = idx / n_groups;
    int g = idx - k * n_groups;
    int expert = indices[k];
    float score = scores[k];

    ulong w_expert_byte_off = (ulong)(uint)expert * (ulong)(uint)n_out * (ulong)((uint)u32s_per_row * 4u);
    ulong s_expert_byte_off = (ulong)(uint)expert * (ulong)(uint)n_out * (ulong)(uint)n_groups;

    device const uchar *w_row = w_base + w_expert_byte_off
                                + (ulong)(uint)m * (ulong)((uint)u32s_per_row * 4u)
                                + (ulong)((uint)g * 8u);
    device const uchar *s_pos = s_base + s_expert_byte_off
                                + (ulong)(uint)m * (ulong)(uint)n_groups
                                + (ulong)(uint)g;

    uint w0 = load_u32_le(w_row);
    uint w1 = load_u32_le(w_row + 4);
    half scale_h = e4m3_decode_half((uint)*s_pos);
    float scale = float(scale_h);

    int x_off = k * k_dim + g * 16;
    float h[16];
    for (int j = 0; j < 16; j++) {
      float gv = gate[x_off + j];
      float uv = up[x_off + j];
      float sig = 1.0f / (1.0f + exp(-gv));
      h[j] = (gv * sig) * uv;
    }

    uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF, b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
    float4 wv0 = float4(
        nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4),
        nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));
    float4 wv1 = float4(
        nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4),
        nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));
    uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF, b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;
    float4 wv2 = float4(
        nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4),
        nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));
    float4 wv3 = float4(
        nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4),
        nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));

    float4 h0 = float4(h[0], h[1], h[2], h[3]);
    float4 h1 = float4(h[4], h[5], h[6], h[7]);
    float4 h2 = float4(h[8], h[9], h[10], h[11]);
    float4 h3 = float4(h[12], h[13], h[14], h[15]);

    float dp = dot(wv0, h0) + dot(wv1, h1) + dot(wv2, h2) + dot(wv3, h3);
    partial += score * scale * dp;
  }

  float total = simd_sum(partial);
  if (lane == 0) y[m] = y[m] + total;
}
