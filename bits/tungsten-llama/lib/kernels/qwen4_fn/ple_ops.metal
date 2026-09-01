// PLE (n-gram per-layer embedding) device pieces for Qwen4Exp, decode step.
// The n-gram hash + fp8 table gather happen on the HOST (16 rows x 160 bytes
// per token from a 51GB mmap); these kernels run everything after the
// key/value projections:
//
//   ple_gate:  per-stream scalar gate and value broadcast
//     gate_s = sigmoid( signed_sqrt( dot(kn[s], qn[s]) / sqrt(d) ) )
//     gv[s*d + i] = gate_s * v[i]
//   ple_conv_dilated_step: depthwise kernel-4 dilation-3 causal conv over the
//     norm_conv output, + silu, then the final H update in place:
//     H[c] += gv[c] + silu(conv(nc)[c])
//     State: [9, C] older-first ring of nc history (taps at rows 0,3,6 + new).
//
// Dispatch: ple_gate = S TGs x 256; conv = C threads.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void ple_gate(
  device const float *__restrict__ kn [[buffer(0)]],   // [S * d] normed keys
  device const float *__restrict__ qn [[buffer(1)]],   // [S * d] normed queries
  device const float *__restrict__ v  [[buffer(2)]],   // [d]
  device       float *__restrict__ gv [[buffer(3)]],   // [S * d]
  constant int &d [[buffer(4)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  int base = int(__tg_id) * d;
  float dp = 0.0f;
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    dp += kn[base + i] * qn[base + i];
  }
  threadgroup float __tg_scratch_f[32];
  float sm = simd_sum(dp);
  if (__simd_lane == 0) __tg_scratch_f[__simd_id] = sm;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  uint n_simds = __tg_size / 32;
  float partial = (__simd_lane < n_simds) ? __tg_scratch_f[__simd_lane] : 0.0f;
  float total = (__simd_id == 0) ? simd_sum(partial) : 0.0f;
  if (__simd_id == 0 && __simd_lane == 0) __tg_scratch_f[0] = total;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  total = __tg_scratch_f[0] / sqrt(float(d));

  // signed sqrt, then sigmoid
  float mag = sqrt(max(fabs(total), 1.0e-6f));
  float signed_sqrt = (total < 0.0f) ? -mag : mag;
  float gate = 1.0f / (1.0f + exp(-signed_sqrt));

  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    gv[base + i] = gate * v[i];
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void ple_conv_dilated_step(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [9, C] older first
  device const float *__restrict__ nc        [[buffer(2)]],   // [C] new conv input
  device const float *__restrict__ gv        [[buffer(3)]],   // [C]
  device       float *__restrict__ H         [[buffer(4)]],   // [C], updated in place
  device       float *__restrict__ state_out [[buffer(5)]],   // [9, C]
  constant int &C [[buffer(6)]],
  uint __tid [[thread_position_in_grid]]
) {
  int c = int(__tid);
  if (c >= C) return;

  // Dilation-3 taps over [state | nc]: t-9, t-6, t-3, t.
  float s0 = state[0 * C + c];
  float s3 = state[3 * C + c];
  float s6 = state[6 * C + c];
  float x_new = nc[c];

  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  float conv_out = w0 * s0 + w1 * s3 + w2 * s6 + w3 * x_new;
  float sig = 1.0f / (1.0f + exp(-conv_out));

  H[c] += gv[c] + conv_out * sig;

  // Slide the 9-deep ring by one.
  for (int r = 0; r < 8; r++) {
    state_out[r * C + c] = state[(r + 1) * C + c];
  }
  state_out[8 * C + c] = x_new;
}
