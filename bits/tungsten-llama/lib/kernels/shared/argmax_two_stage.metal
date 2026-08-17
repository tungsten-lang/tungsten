// Parallel exact argmax for one or more rows of a logits matrix.
//
// Stage 1 reduces 1024 logits per threadgroup. Stage 2 reduces those partials
// to one (value, lowest-index) pair per batch row. This replaces the old
// single-simdgroup scan, which serialized 248K vocabulary entries per lane.

#include <metal_stdlib>
using namespace metal;

constant uint ARGMAX_CHUNK = 1024;

static inline void argmax_merge(thread float &best_v, thread int &best_i,
                                float other_v, int other_i) {
  if (other_v > best_v || (other_v == best_v && other_i < best_i)) {
    best_v = other_v;
    best_i = other_i;
  }
}

static inline void argmax_simd_reduce(thread float &best_v,
                                      thread int &best_i) {
  for (uint offset = 16; offset > 0; offset >>= 1) {
    const float other_v = simd_shuffle_xor(best_v, offset);
    const int other_i = simd_shuffle_xor(best_i, offset);
    argmax_merge(best_v, best_i, other_v, other_i);
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void argmax_stage1(
  device const float *__restrict__ logits [[buffer(0)]],
  device float *__restrict__ partial_values [[buffer(1)]],
  device int *__restrict__ partial_indices [[buffer(2)]],
  constant int &n [[buffer(3)]],
  constant int &chunks_per_row [[buffer(4)]],
  constant int &batch [[buffer(5)]],
  uint tg [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float group_values[8];
  threadgroup int group_indices[8];
  const int row = int(tg) / chunks_per_row;
  const int chunk = int(tg) - row * chunks_per_row;
  if (row >= batch) return;
  const int start = chunk * int(ARGMAX_CHUNK);
  const int end = min(start + int(ARGMAX_CHUNK), n);
  float best_v = -INFINITY;
  int best_i = INT_MAX;
  for (int i = start + int(tid); i < end; i += 256) {
    const float v = logits[row * n + i];
    argmax_merge(best_v, best_i, v, i);
  }
  argmax_simd_reduce(best_v, best_i);
  if (lane == 0) {
    group_values[simd] = best_v;
    group_indices[simd] = best_i;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (simd == 0) {
    best_v = lane < 8 ? group_values[lane] : -INFINITY;
    best_i = lane < 8 ? group_indices[lane] : INT_MAX;
    argmax_simd_reduce(best_v, best_i);
    if (lane == 0) {
      const int out = row * chunks_per_row + chunk;
      partial_values[out] = best_v;
      partial_indices[out] = best_i;
    }
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void argmax_stage2(
  device const float *__restrict__ partial_values [[buffer(0)]],
  device const int *__restrict__ partial_indices [[buffer(1)]],
  device int *__restrict__ result [[buffer(2)]],
  constant int &chunks_per_row [[buffer(3)]],
  constant int &batch [[buffer(4)]],
  uint row [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float group_values[8];
  threadgroup int group_indices[8];
  if (int(row) >= batch) return;
  float best_v = -INFINITY;
  int best_i = INT_MAX;
  const int base = int(row) * chunks_per_row;
  for (int chunk = int(tid); chunk < chunks_per_row; chunk += 256) {
    argmax_merge(best_v, best_i, partial_values[base + chunk],
                 partial_indices[base + chunk]);
  }
  argmax_simd_reduce(best_v, best_i);
  if (lane == 0) {
    group_values[simd] = best_v;
    group_indices[simd] = best_i;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (simd == 0) {
    best_v = lane < 8 ? group_values[lane] : -INFINITY;
    best_i = lane < 8 ? group_indices[lane] : INT_MAX;
    argmax_simd_reduce(best_v, best_i);
    if (lane == 0) result[row] = best_i;
  }
}
