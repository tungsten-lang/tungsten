// Argmax over n floats. 1 TG of 1024 threads (32 simdgroups × 32 lanes) —
// 32× the parallelism of the original 32-thread kernel that this replaces.
// Single-pass: each thread tracks (max_val, max_idx); reduce within simdgroup,
// then reduce across simdgroups via threadgroup memory. Tie-breaking picks
// the smallest index (canonical argmax for sampling).
//
// Workload at n=151936: each lane scans ~148 elements (down from 4748),
// total kernel time drops from ~300µs to ~10µs.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(1024)]]
kernel void argmax_v2(
  device const float *x  [[buffer(0)]],
  device int         *result [[buffer(1)]],
  constant int &n        [[buffer(2)]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]]
) {
  const int TG_SIZE = 1024;
  const int N_SIMDS = 32;

  // Each thread scans its strided slice of x, tracking the running max.
  float my_max = -INFINITY;
  int   my_idx = 0;
  for (int i = int(__tid_in_tg); i < n; i += TG_SIZE) {
    float v = x[i];
    if (v > my_max) { my_max = v; my_idx = i; }
  }

  // Reduce within this simdgroup (32 lanes).
  float sm_max = simd_max(my_max);
  // Tie-break: among lanes whose value == sm_max, pick the smallest index.
  int sm_idx = (my_max == sm_max) ? my_idx : INT_MAX;
  sm_idx = simd_min(sm_idx);

  // Cross-simdgroup reduce via threadgroup memory.
  threadgroup float tg_max[N_SIMDS];
  threadgroup int   tg_idx[N_SIMDS];
  if (__simd_lane == 0) {
    tg_max[__simd_id] = sm_max;
    tg_idx[__simd_id] = sm_idx;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Final reduction in simdgroup 0 (which has 32 lanes, exactly N_SIMDS).
  if (__simd_id == 0) {
    float v   = tg_max[__simd_lane];
    int   idx = tg_idx[__simd_lane];
    float gmax = simd_max(v);
    int   gidx = (v == gmax) ? idx : INT_MAX;
    gidx = simd_min(gidx);
    if (__simd_lane == 0) {
      result[0] = gidx;
    }
  }
}
