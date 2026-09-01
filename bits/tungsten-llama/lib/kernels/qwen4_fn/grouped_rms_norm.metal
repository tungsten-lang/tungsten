// grouped_rms_norm: per-group RMSNorm over a [groups, group_size] view with a
// full-width affine weight (weight already carries the Gemma-style +1, the
// loader adds it).
//
// Qwen4Exp hyper-connections normalize the 4x2560 residual stream per 2560
// stream while keeping a separate affine weight for every element of the
// 10240 layout; the PLE norms and the final hyper_connection_mixer use the
// same shape. fp32 math throughout.
//
//   n[s, i] = x[s, i] * rsqrt(mean_i(x[s, i]^2) + eps) * w[s * d + i]
//
// Dispatch: metal_dispatch_groups(queue, pipe, [x, w, y, d, eps], groups, 256)

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void grouped_rms_norm(
  device const float *__restrict__ x [[buffer(0)]],   // [groups * d]
  device const float *__restrict__ w [[buffer(1)]],   // [groups * d], includes +1
  device       float *__restrict__ y [[buffer(2)]],   // [groups * d]
  constant int   &d   [[buffer(3)]],
  constant float &eps [[buffer(4)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  int base = int(__tg_id) * d;
  float sum_sq = 0.0f;
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    float v = x[base + i];
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

  float rrms = 1.0f / sqrt(total / float(d) + eps);
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    y[base + i] = x[base + i] * rrms * w[base + i];
  }
}
