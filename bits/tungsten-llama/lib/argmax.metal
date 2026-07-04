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
kernel void argmax(
  device float *x [[buffer(0)]],
  device int *result [[buffer(1)]],
  constant int &n [[buffer(2)]],
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
  float m_local = -1000000000.0f;
  int i = tid;
  while ((i < n)) {
    float v = x[i];
    if ((v > m_local)) {
      m_local = v;
    }
    i = (i + tg_size);
  }
  float m = __tg_max_f32(m_local, __tg_scratch_f, __simd_lane, __simd_id);
  int best = n;
  i = tid;
  while ((i < n)) {
    if ((x[i] == m)) {
      if ((i < best)) {
        best = i;
      }
    }
    i = (i + tg_size);
  }
  int g_best = __tg_min_i32(best, __tg_scratch_i, __simd_lane, __simd_id);
  if ((tid == 0)) {
    result[0] = g_best;
  }
}

