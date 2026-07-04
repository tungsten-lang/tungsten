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
kernel void attn_scores(
  device float *q [[buffer(0)]],
  device float *k_cache [[buffer(1)]],
  device float *scores [[buffer(2)]],
  constant int &head_dim [[buffer(3)]],
  constant int &n_kv_heads [[buffer(4)]],
  constant int &group_size [[buffer(5)]],
  constant int &n_pos [[buffer(6)]],
  constant float &scale [[buffer(7)]],
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
  int cell = int(__tg_id);
  int h = (cell / n_pos);
  int t = (cell % n_pos);
  int kv_h = (h / group_size);
  int q_off = (h * head_dim);
  int k_off = (((t * n_kv_heads) + kv_h) * head_dim);
  float partial = 0.0f;
  int j = tid;
  while ((j < head_dim)) {
    partial = (partial + (q[(q_off + j)] * k_cache[(k_off + j)]));
    j = (j + tg_size);
  }
  float total = __tg_sum_f32(partial, __tg_scratch_f, __simd_lane, __simd_id, __tg_size / 32);
  if ((tid == 0)) {
    scores[((h * n_pos) + t)] = (total * scale);
  }
}

