// RMSNorm with proper threadgroup parallelism. 1 TG of 256 threads
// (8 simdgroups × 32 lanes) — replaces the @gpu-emitted single-simdgroup
// kernel that scaled poorly when called 57×/token at HIDDEN=2048.
//
// Per HIDDEN=2048 vector: each lane sums squares of 8 elements, simdgroup
// reduce, cross-simdgroup reduce in TG memory, broadcast rrms, scale + γ
// in the same striding pattern. Per-call cost drops from ~10µs to ~2µs.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void rms_norm_v2(
  device const float *x [[buffer(0)]],
  device const float *w [[buffer(1)]],
  device float       *y [[buffer(2)]],
  constant int   &n     [[buffer(3)]],
  constant float &inv_n [[buffer(4)]],
  constant float &eps   [[buffer(5)]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]]
) {
  const int TG_SIZE = 256;
  const int N_SIMDS = 8;

  // Sum-of-squares pass: each thread strides through its slice of x.
  float sum_sq = 0.0f;
  for (int i = int(__tid_in_tg); i < n; i += TG_SIZE) {
    float v = x[i];
    sum_sq += v * v;
  }

  // Reduce within simdgroup.
  float sm_sum = simd_sum(sum_sq);

  // Cross-simdgroup reduce via threadgroup memory (one slot per simdgroup).
  threadgroup float tg_sum[N_SIMDS];
  if (__simd_lane == 0) tg_sum[__simd_id] = sm_sum;
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Final reduction in simdgroup 0: 8 lanes load, simd_sum across the
  // first 8 lanes (other lanes contribute 0).
  threadgroup float total_bcast;
  if (__simd_id == 0) {
    float partial = (int(__simd_lane) < N_SIMDS) ? tg_sum[__simd_lane] : 0.0f;
    float total = simd_sum(partial);
    if (__simd_lane == 0) {
      total_bcast = total;
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  float rrms = 1.0f / sqrt(total_bcast * inv_n + eps);

  // Apply: y[i] = x[i] * rrms * w[i], same striding.
  for (int i = int(__tid_in_tg); i < n; i += TG_SIZE) {
    y[i] = (x[i] * rrms) * w[i];
  }
}
