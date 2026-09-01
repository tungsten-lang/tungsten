// Deep-fused hyper-connection mix for the NVFP4 self-quant path.
//
// Ablation priced the HC chains at ~8ms/token — ~0.7ms of weight stream and
// the rest serial-stage latency (96 chains x ~6 dependent stages). These two
// kernels collapse the five mix stages (grouped norm, down matvec, silu/4,
// up matvec, sigmoid-weighted mean — plus the inject matvec) into two,
// never materializing the normalized stream n: every threadgroup recomputes
// the four per-stream RMS scalars from H on the fly (40KB of redundant
// reads, noise next to the launch latency it saves).
//
//   stage A: rms[4] from H; g[r] = silu(dot(W_down[r], n)/4) for r<320,
//            inj_raw[s] = dot(W_inject[s], n) (bf16 rows), rms out.
//            n[i] == H[i] * rms[i/2560] * norm_w[i]  (norm_w carries the +1)
//   stage B: x[i] = mean_s sigmoid(dot(W_up[s*2560+i], g)) * n(s,i)
//
// W_down/W_up are NVFP4 triples (packed u32-aligned, e4m3 group-16 scales,
// f32 global scale); the bf16 fallback layers keep the unfused path.
//
// Dispatch: A = 162 TGs x 64 (2 simdgroups, 1 row each; rows 320..323 are
// the inject rows); B = 10 TGs x 256 (one output element per thread).

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

static inline float bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

#define HC_S 4
#define HC_H 2560
#define HC_HH 10240
#define HC_R 320

// Cooperative per-stream RMS over H: every thread accumulates group-wise
// sum-of-squares, TG-reduces, returns rsqrt(mean + eps) per stream.
static inline void hc_rms(device const float *H, float eps,
                          threadgroup float *scratch,
                          uint tid, uint tg_size, uint simd_lane, uint simd_id,
                          thread float rms[HC_S]) {
  float acc[HC_S] = {0.0f, 0.0f, 0.0f, 0.0f};
  for (int i = int(tid); i < HC_HH; i += int(tg_size)) {
    float v = H[i];
    acc[i / HC_H] += v * v;
  }
  uint n_simds = tg_size / 32;
  for (int s = 0; s < HC_S; s++) {
    float sm = simd_sum(acc[s]);
    if (simd_lane == 0) scratch[simd_id * HC_S + s] = sm;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int s = 0; s < HC_S; s++) {
    float total = 0.0f;
    for (uint g = 0; g < n_simds; g++) total += scratch[g * HC_S + s];
    rms[s] = 1.0f / sqrt(total / float(HC_H) + eps);
  }
}

[[max_total_threads_per_threadgroup(64)]]
kernel void hc_mix_a(
  device const float  *__restrict__ H       [[buffer(0)]],
  device const float  *__restrict__ norm_w  [[buffer(1)]],   // includes +1
  device const uint   *__restrict__ dw      [[buffer(2)]],   // W_down nvfp4 [320, 10240]
  device const uchar  *__restrict__ ds      [[buffer(3)]],
  device const float  *__restrict__ dg      [[buffer(4)]],
  device const ushort *__restrict__ inj_w   [[buffer(5)]],   // bf16 [4, 10240]
  device float        *__restrict__ g_out   [[buffer(6)]],   // [320] post-silu
  device float        *__restrict__ inj_out [[buffer(7)]],   // [4]
  device float        *__restrict__ rms_out [[buffer(8)]],   // [4]
  constant float &eps [[buffer(9)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  threadgroup float scratch[2 * HC_S];
  float rms[HC_S];
  hc_rms(H, eps, scratch, __tid_in_tg, __tg_size, __simd_lane, __simd_id, rms);

  int row = int(__tg_id) * 2 + int(__simd_id);
  int lane = int(__simd_lane);
  if (row >= HC_R + HC_S) return;

  float partial = 0.0f;
  if (row < HC_R) {
    // NVFP4 row dot against n computed on the fly. 640 groups of 16; every
    // group sits inside ONE stream (2560/16=160), so rms is group-uniform.
    const int n_groups = HC_HH / 16;
    const int u32s_per_row = HC_HH / 8;
    for (int g = lane; g < n_groups; g += 32) {
      uint w0 = dw[row * u32s_per_row + g * 2];
      uint w1 = dw[row * u32s_per_row + g * 2 + 1];
      float scale = float(e4m3_decode_half(uint(ds[row * n_groups + g])));
      int base = g * 16;
      float rms_g = rms[base / HC_H];
      device const float4 *Hp = (device const float4 *)(&H[base]);
      device const float4 *Wp = (device const float4 *)(&norm_w[base]);
      uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF;
      uint b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
      uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF;
      uint b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;
      float4 wv0 = float4(nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4), nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));
      float4 wv1 = float4(nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4), nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));
      float4 wv2 = float4(nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4), nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));
      float4 wv3 = float4(nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4), nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));
      float dp = dot(wv0, Hp[0] * Wp[0]) + dot(wv1, Hp[1] * Wp[1])
               + dot(wv2, Hp[2] * Wp[2]) + dot(wv3, Hp[3] * Wp[3]);
      partial += scale * rms_g * dp;
    }
    float total = simd_sum(partial) * dg[0];
    if (lane == 0) {
      float v = total / float(HC_S);
      g_out[row] = v / (1.0f + exp(-v));            // silu(dot / 4)
    }
  } else {
    int r = row - HC_R;
    for (int i = lane; i < HC_HH; i += 32) {
      float n = H[i] * rms[i / HC_H] * norm_w[i];
      partial += bf16_to_f32(inj_w[r * HC_HH + i]) * n;
    }
    float total = simd_sum(partial);
    if (lane == 0) inj_out[r] = total;
  }
  if (row == 0 && lane < HC_S) rms_out[lane] = rms[lane];
}

[[max_total_threads_per_threadgroup(256)]]
kernel void hc_mix_b(
  device const float *__restrict__ H      [[buffer(0)]],
  device const float *__restrict__ norm_w [[buffer(1)]],
  device const uint  *__restrict__ uw     [[buffer(2)]],   // W_up nvfp4 [10240, 320]
  device const uchar *__restrict__ us     [[buffer(3)]],
  device const float *__restrict__ ug     [[buffer(4)]],
  device const float *__restrict__ g_in   [[buffer(5)]],   // [320]
  device const float *__restrict__ rms_in [[buffer(6)]],   // [4]
  device float       *__restrict__ x_out  [[buffer(7)]],   // [2560]
  uint __tid       [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  threadgroup float g_sh[HC_R];
  for (int i = int(__tid_in_tg); i < HC_R; i += int(__tg_size)) {
    g_sh[i] = g_in[i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  int i = int(__tid);
  if (i >= HC_H) return;
  const int n_groups = HC_R / 16;          // 20
  const int u32s_per_row = HC_R / 8;       // 40
  float gscale = ug[0];
  float acc = 0.0f;
  for (int s = 0; s < HC_S; s++) {
    int row = s * HC_H + i;
    float dp_row = 0.0f;
    for (int g = 0; g < n_groups; g++) {
      uint w0 = uw[row * u32s_per_row + g * 2];
      uint w1 = uw[row * u32s_per_row + g * 2 + 1];
      float scale = float(e4m3_decode_half(uint(us[row * n_groups + g])));
      threadgroup const float4 *gp = (threadgroup const float4 *)(&g_sh[g * 16]);
      uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF;
      uint b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
      uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF;
      uint b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;
      float4 wv0 = float4(nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4), nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4));
      float4 wv1 = float4(nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4), nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4));
      float4 wv2 = float4(nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4), nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4));
      float4 wv3 = float4(nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4), nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4));
      float dp = dot(wv0, gp[0]) + dot(wv1, gp[1]) + dot(wv2, gp[2]) + dot(wv3, gp[3]);
      dp_row += scale * dp;
    }
    float up = dp_row * gscale;
    float gate = 1.0f / (1.0f + exp(-up));
    float n = H[row] * rms_in[s] * norm_w[row];
    acc += gate * n;
  }
  x_out[i] = acc / float(HC_S);
}
