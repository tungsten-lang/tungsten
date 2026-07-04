// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

// Threadgroup-wide reductions across up to 1024 threads (32 simdgroups).
inline float __tg_sum_f32(float v, threadgroup float *s, uint sl, uint si) {
  if (si == 0) { s[sl] = 0.0f; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float sm = simd_sum(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float total = (si == 0) ? simd_sum(s[sl]) : 0.0f;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline float __tg_max_f32(float v, threadgroup float *s, uint sl, uint si) {
  if (si == 0) { s[sl] = -INFINITY; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float sm = simd_max(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float total = (si == 0) ? simd_max(s[sl]) : -INFINITY;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline int __tg_min_i32(int v, threadgroup int *s, uint sl, uint si) {
  if (si == 0) { s[sl] = INT_MAX; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int sm = simd_min(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int total = (si == 0) ? simd_min(s[sl]) : INT_MAX;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void rms_norm(
  device float *x [[buffer(0)]],
  device float *w [[buffer(1)]],
  device float *y [[buffer(2)]],
  constant int &n [[buffer(3)]],
  constant float &inv_n [[buffer(4)]],
  constant float &eps [[buffer(5)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]],
  uint __tg_size [[threads_per_threadgroup]]
) {
  threadgroup float __tg_scratch_f[32];
  threadgroup int   __tg_scratch_i[32];
  int tg_size = int(__tg_size);
  int tid = int(__tid_in_tg);
  float sum_sq = 0.0f;
  int i = tid;
  while ((i < n)) {
    float v = x[i];
    sum_sq = (sum_sq + (v * v));
    i = (i + tg_size);
  }
  float total = __tg_sum_f32(sum_sq, __tg_scratch_f, __simd_lane, __simd_id);
  float rrms = (1.0f / sqrt(((total * inv_n) + eps)));
  i = tid;
  while ((i < n)) {
    y[i] = ((x[i] * rrms) * w[i]);
    i = (i + tg_size);
  }
}

