// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

// Threadgroup-wide reductions across up to 1024 threads (32 simdgroups).
inline float __tg_sum_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_sum(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : 0.0f;
  float total = (si == 0) ? simd_sum(partial) : 0.0f;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline float __tg_max_f32(float v, threadgroup float *s, uint sl, uint si, uint n_simds) {
  float sm = simd_max(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float partial = (sl < n_simds) ? s[sl] : -INFINITY;
  float total = (si == 0) ? simd_max(partial) : -INFINITY;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}
inline int __tg_min_i32(int v, threadgroup int *s, uint sl, uint si, uint n_simds) {
  int sm = simd_min(v);
  if (sl == 0) { s[si] = sm; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int partial = (sl < n_simds) ? s[sl] : INT_MAX;
  int total = (si == 0) ? simd_min(partial) : INT_MAX;
  if (si == 0 && sl == 0) { s[0] = total; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  return s[0];
}

[[max_total_threads_per_threadgroup(1024)]]
kernel void attn_softmax(
  device float *x [[buffer(0)]],
  constant int &n [[buffer(1)]],
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
  int row = int(__tg_id);
  int tid = int(__tid_in_tg);
  int base = (row * n);
  float m_local = -1000000000.0f;
  int i = tid;
  while ((i < n)) {
    float v = x[(base + i)];
    if ((v > m_local)) {
      m_local = v;
    }
    i = (i + tg_size);
  }
  float m = __tg_max_f32(m_local, __tg_scratch_f, __simd_lane, __simd_id, __tg_size / 32);
  float s_local = 0.0f;
  i = tid;
  while ((i < n)) {
    s_local = (s_local + exp((x[(base + i)] - m)));
    i = (i + tg_size);
  }
  float s = __tg_sum_f32(s_local, __tg_scratch_f, __simd_lane, __simd_id, __tg_size / 32);
  float inv_s = (1.0f / s);
  i = tid;
  while ((i < n)) {
    x[(base + i)] = (exp((x[(base + i)] - m)) * inv_s);
    i = (i + tg_size);
  }
}

