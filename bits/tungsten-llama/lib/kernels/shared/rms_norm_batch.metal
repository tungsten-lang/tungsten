// Runtime-width RMS normalization, one threadgroup per row.
// Supports autotuning the reduction width without function specialization.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(512)]]
kernel void rms_norm_batch(
  device const float *__restrict__ x [[buffer(0)]],
  device const float *__restrict__ w [[buffer(1)]],
  device float *__restrict__ y [[buffer(2)]],
  constant int &n [[buffer(3)]],
  constant int &batch [[buffer(4)]],
  constant float &inv_n [[buffer(5)]],
  constant float &eps [[buffer(6)]],
  uint row [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]],
  uint tg_size [[threads_per_threadgroup]]) {
  threadgroup float partial[16];
  if (int(row) >= batch) return;
  const int base = int(row) * n;
  float sum_sq = 0.0f;
  for (int i = int(tid); i < n; i += int(tg_size)) {
    const float v = x[base + i];
    sum_sq += v * v;
  }
  const float simd_total = simd_sum(sum_sq);
  if (lane == 0) partial[simd] = simd_total;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (simd == 0) {
    const uint n_simds = tg_size / 32;
    const float v = lane < n_simds ? partial[lane] : 0.0f;
    const float total = simd_sum(v);
    if (lane == 0) partial[0] = total;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  const float rrms = rsqrt(partial[0] * inv_n + eps);
  for (int i = int(tid); i < n; i += int(tg_size)) {
    y[base + i] = x[base + i] * rrms * w[i];
  }
}
