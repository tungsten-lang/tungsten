// Four/five-token NVFP4 matrix-vector batches for deep MTP verification.
// One SIMD group owns one output row and reuses each decoded weight group
// across every activation row. Two SIMD groups run per threadgroup.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half_batch(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_batch(uint byte) {
  return as_type<half>(ushort((byte & 127) << 7)) * 256.0h;
}

template <int BATCH, bool ADD_RESIDUAL>
static inline void nvfp4_matvec_mlx_scaled_batch_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  uint tg,
  uint simd_id,
  uint lane
) {
  const int row = int(tg) * 2 + int(simd_id);
  if (row >= n_rows) return;

  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  float a0 = 0.0f, a1 = 0.0f, a2 = 0.0f, a3 = 0.0f, a4 = 0.0f;

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int group = g_block + int(lane);
    if (group >= n_groups) continue;

    const int x_off = group * 16;
    device const float4 *x0 = (device const float4 *)(&x[x_off]);
    device const float4 *x1 = (device const float4 *)(&x[k_dim + x_off]);
    device const float4 *x2 = (device const float4 *)(&x[2 * k_dim + x_off]);
    device const float4 *x3 = (device const float4 *)(&x[3 * k_dim + x_off]);
    device const float4 *x4 = (device const float4 *)(&x[4 * k_dim + x_off]);

    const uint w0 = w_packed[row * u32s_per_row + group * 2];
    const uint w1 = w_packed[row * u32s_per_row + group * 2 + 1];
    const float scale = float(e4m3_decode_half_batch(
      uint(w_scales[row * n_groups + group])));

    const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
    const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
    const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
    const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
    const float4 v0 = float4(nvfp4_decode_half_batch(b00 & 0xf),
      nvfp4_decode_half_batch(b00 >> 4), nvfp4_decode_half_batch(b01 & 0xf),
      nvfp4_decode_half_batch(b01 >> 4));
    const float4 v1 = float4(nvfp4_decode_half_batch(b02 & 0xf),
      nvfp4_decode_half_batch(b02 >> 4), nvfp4_decode_half_batch(b03 & 0xf),
      nvfp4_decode_half_batch(b03 >> 4));
    const float4 v2 = float4(nvfp4_decode_half_batch(b10 & 0xf),
      nvfp4_decode_half_batch(b10 >> 4), nvfp4_decode_half_batch(b11 & 0xf),
      nvfp4_decode_half_batch(b11 >> 4));
    const float4 v3 = float4(nvfp4_decode_half_batch(b12 & 0xf),
      nvfp4_decode_half_batch(b12 >> 4), nvfp4_decode_half_batch(b13 & 0xf),
      nvfp4_decode_half_batch(b13 >> 4));

#define BATCH_DOT(XP) (dot(v0, (XP)[0]) + dot(v1, (XP)[1]) + \
                       dot(v2, (XP)[2]) + dot(v3, (XP)[3]))
    a0 += scale * BATCH_DOT(x0);
    if (BATCH >= 2) a1 += scale * BATCH_DOT(x1);
    if (BATCH >= 3) a2 += scale * BATCH_DOT(x2);
    if (BATCH >= 4) a3 += scale * BATCH_DOT(x3);
    if (BATCH >= 5) a4 += scale * BATCH_DOT(x4);
#undef BATCH_DOT
  }

  a0 = simd_sum(a0) * global_scale;
  if (BATCH >= 2) a1 = simd_sum(a1) * global_scale;
  if (BATCH >= 3) a2 = simd_sum(a2) * global_scale;
  if (BATCH >= 4) a3 = simd_sum(a3) * global_scale;
  if (BATCH >= 5) a4 = simd_sum(a4) * global_scale;

  if (lane == 0) {
#define BATCH_STORE(B, V) do {                                              \
    if (ADD_RESIDUAL) y[(B) * n_rows + row] += (V);                         \
    else y[(B) * n_rows + row] = (V);                                      \
  } while (false)
    BATCH_STORE(0, a0);
    if (BATCH >= 2) { BATCH_STORE(1, a1); }
    if (BATCH >= 3) { BATCH_STORE(2, a2); }
    if (BATCH >= 4) { BATCH_STORE(3, a3); }
    if (BATCH >= 5) { BATCH_STORE(4, a4); }
#undef BATCH_STORE
  }
}

#define DEFINE_BATCH_KERNEL(NAME, BATCH, ADD_RESIDUAL)                      \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_matvec_mlx_scaled_batch_impl<BATCH, ADD_RESIDUAL>(                  \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}

DEFINE_BATCH_KERNEL(nvfp4_matvec_mlx_scaled_quad, 4, false)
DEFINE_BATCH_KERNEL(nvfp4_matvec_mlx_scaled_quad_residual, 4, true)
DEFINE_BATCH_KERNEL(nvfp4_matvec_mlx_scaled_quint, 5, false)
DEFINE_BATCH_KERNEL(nvfp4_matvec_mlx_scaled_quint_residual, 5, true)

#undef DEFINE_BATCH_KERNEL
