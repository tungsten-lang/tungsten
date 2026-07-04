// rms_norm_gated: per-head RMSNorm × silu(gate).
//
// Used post-Mamba in qwen3.6's GatedDeltaNet:
//   x = rms_norm(h, weight, eps) over Dv per head
//   out = silu(gate) * x          (cast to f32 for the multiply, then back)
//
// One TG per (b, t, hv) cell. TG_SIZE threads cooperate over Dv elements.
// For qwen3.6 decode: B=1, T=1, Hv=32 → 32 TGs; Dv=128 → use TG=32 (one
// simdgroup, 4 elts/lane is plenty for Dv=128).
//
// Layout:
//   h:      [B, T, Hv, Dv]
//   gate:   [B, T, Hv, Dv]   (or [B, T, Hv*Dv] flattened — same memory)
//   weight: [Dv]             (shared per-head)
//   out:    [B, T, Hv, Dv]

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void rms_norm_gated(
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
  // Each TG handles one (b, t, hv) cell. Base offset into h/gate/out for this cell.
  int cell_off = int(__tg_id) * dv;

  // Sum-of-squares of h over Dv, lane-strided.
  float sum_sq = 0.0f;
  for (int i = int(__tid_in_tg); i < dv; i += int(__tg_size)) {
    float v = h[cell_off + i];
    sum_sq += v * v;
  }

  // Cross-simdgroup reduce via threadgroup memory (TG-wide sum). For TG=32
  // this degenerates to single simd_sum; for larger TGs reduces across.
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

  // Apply: out[i] = silu(gate[i]) * (h[i] * rrms * weight[i])
  for (int i = int(__tid_in_tg); i < dv; i += int(__tg_size)) {
    float g = gate[cell_off + i];
    float silu_g = g / (1.0f + exp(-g));     // silu(x) = x * sigmoid(x)
    float x = h[cell_off + i] * rrms * weight[i];
    out[cell_off + i] = silu_g * x;
  }
}
