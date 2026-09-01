// rms_norm_gated_sig: per-head RMSNorm × sigmoid(gate).
//
// Qwen4Exp's GDN output gate is SIGMOID (config output_gate_type), unlike
// Qwen3.5/3.6's silu — this is qwen3_6/rms_norm_gated.metal with the gate
// activation swapped. The norm weight is PLAIN w (ones-centered), the one
// norm in this model that is not (1+w).
//
//   x   = rms_norm(h, weight, eps) over Dv per head
//   out = sigmoid(gate) * x
//
// One TG per (b, t, hv) cell; TG=32 for Dv=128.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void rms_norm_gated_sig(
  device const float *__restrict__ h      [[buffer(0)]],
  device const float *__restrict__ gate   [[buffer(1)]],
  device const float *__restrict__ weight [[buffer(2)]],
  device       float *__restrict__ out    [[buffer(3)]],
  constant int   &dv  [[buffer(4)]],
  constant float &eps [[buffer(5)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  int cell_off = int(__tg_id) * dv;

  float sum_sq = 0.0f;
  for (int i = int(__tid_in_tg); i < dv; i += int(__tg_size)) {
    float v = h[cell_off + i];
    sum_sq += v * v;
  }

  threadgroup float __tg_scratch_f[32];
  float sm = simd_sum(sum_sq);
  if (__simd_lane == 0) __tg_scratch_f[__simd_id] = sm;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  uint n_simds = __tg_size / 32;
  float partial = (__simd_lane < n_simds) ? __tg_scratch_f[__simd_lane] : 0.0f;
  float total = (__simd_id == 0) ? simd_sum(partial) : 0.0f;
  if (__simd_id == 0 && __simd_lane == 0) __tg_scratch_f[0] = total;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  total = __tg_scratch_f[0];

  float rrms = 1.0f / sqrt(total / float(dv) + eps);

  for (int i = int(__tid_in_tg); i < dv; i += int(__tg_size)) {
    float g = gate[cell_off + i];
    float sig_g = 1.0f / (1.0f + exp(-g));
    float x = h[cell_off + i] * rrms * weight[i];
    out[cell_off + i] = sig_g * x;
  }
}
