// moe_gather_matvec: batched top-K routed-expert NVFP4 matvec for Qwen4Exp,
// reading the RadixArk checkpoint's quarter-shard files IN PLACE.
//
// Each layer's 512 experts live in 4 safetensors files (128 experts each),
// mmapped whole and bound as q0..q3. Expert regions inside a file are laid
// out in string-sorted global-id order, so the host passes a slot_map[512]
// (from experts_manifest.json) giving each global expert's slot within its
// quarter. All byte offsets are relative to the FILE START (data_start
// already folded in by the host) and fit comfortably in i32 (<400MB files).
//
// For each (k_idx, m) in [0,K) x [0,n_rows):
//   y[k_idx, m] = ws2(e) * sum_g e4m3(scale[e, m, g]) *
//                          sum_j nvfp4(w[e, m, g, j]) * x[g*16 + j]
// where e = indices[k_idx], nibble low-first, group 16 (ModelOpt NVFP4),
// ws2 = per-expert f32 weight_scale_2 read from the scalars region.
//
// Dispatch: K * (n_rows / 8) TGs of 64 threads (2 simdgroups x 4 rows).

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

static inline float load_f32_le(device const uchar *p) {
  return as_type<float>(load_u32_le(p));
}

[[max_total_threads_per_threadgroup(64)]]
kernel void moe_gather_matvec(
  device const uchar *__restrict__ q0 [[buffer(0)]],   // quarter files, full mmap
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ indices  [[buffer(4)]],   // [K] global expert ids
  device const int   *__restrict__ slot_map [[buffer(5)]],   // [512] slot within quarter
  device const float *__restrict__ x        [[buffer(6)]],   // [k_dim] or [K, k_dim]
  device float       *__restrict__ y        [[buffer(7)]],   // [K, n_rows]
  constant int &k_dim    [[buffer(8)]],
  constant int &n_rows   [[buffer(9)]],
  constant int &x_stride [[buffer(16)]],   // 0 = shared input; k_dim = per-expert rows
  constant int &w0       [[buffer(10)]],   // packed-weight region base (abs file offset)
  constant int &w_stride [[buffer(11)]],   // per-slot stride, bytes
  constant int &s0       [[buffer(12)]],   // scale region base
  constant int &s_stride [[buffer(13)]],
  constant int &g0       [[buffer(14)]],   // weight_scale_2 offset (abs file offset)
  constant int &g_stride [[buffer(15)]],
  device const uchar *__restrict__ hot [[buffer(17)]],  // wired hot-expert overlay
  constant int &hw0 [[buffer(18)]],        // hot-layout bases (same strides)
  constant int &hs0 [[buffer(19)]],
  constant int &hg0 [[buffer(20)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups     = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int tgs_per_k    = n_rows / 8;

  int tg      = int(__tg_id);
  int k_idx   = tg / tgs_per_k;
  int m_block = tg % tgs_per_k;
  int expert  = indices[k_idx];
  int slot    = slot_map[expert];
  int m_start = m_block * 8 + int(__simd_id) * 4;
  int lane    = int(__simd_lane);

  // Bit 30 of the slot map redirects this expert to the wired hot overlay
  // (same strides, its own region bases).
  bool is_hot = (slot & (1 << 30)) != 0;
  device const uchar *base = is_hot ? hot
                           : (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  int bw0 = is_hot ? hw0 : w0;
  int bs0 = is_hot ? hs0 : s0;
  int bg0 = is_hot ? hg0 : g0;
  slot = slot & 0xFFFF;
  device const uchar *w_bytes = base + (ulong)(uint)bw0 + (ulong)(uint)slot * (ulong)(uint)w_stride;
  device const uchar *s_bytes = base + (ulong)(uint)bs0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  float ws2 = load_f32_le(base + (ulong)(uint)bg0 + (ulong)(uint)slot * (ulong)(uint)g_stride);

  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) continue;

    int x_off = k_idx * x_stride + g * 16;
    device const float4 *xp = (device const float4 *)(&x[x_off]);
    float4 x0 = xp[0]; float4 x1 = xp[1];
    float4 x2 = xp[2]; float4 x3 = xp[3];

#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      device const uchar *w_row = w_bytes + (ulong)(uint)row * (ulong)((uint)u32s_per_row * 4u) + (ulong)((uint)g * 8u); \
      uint w0v = load_u32_le(w_row);                                      \
      uint w1v = load_u32_le(w_row + 4);                                  \
      uint sb = (uint)s_bytes[(ulong)(uint)row * (ulong)(uint)n_groups + (ulong)(uint)g]; \
      float scale = float(e4m3_decode_half(sb));                          \
      uint b00 = w0v & 0xFF, b01 = (w0v >>  8) & 0xFF;                    \
      uint b02 = (w0v >> 16) & 0xFF, b03 = (w0v >> 24) & 0xFF;            \
      uint b10 = w1v & 0xFF, b11 = (w1v >>  8) & 0xFF;                    \
      uint b12 = (w1v >> 16) & 0xFF, b13 = (w1v >> 24) & 0xFF;            \
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
    y[y_base + 0] = result0 * ws2;
    y[y_base + 1] = result1 * ws2;
    y[y_base + 2] = result2 * ws2;
    y[y_base + 3] = result3 * ws2;
  }
}
