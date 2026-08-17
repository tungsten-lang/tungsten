// Correct decode-time SDPA for head_dim=256 and short/medium KV caches.
//
// One 256-thread group handles one query head. Each thread owns one output
// dimension; the eight SIMD groups cooperatively reduce q.k for every cached
// position, then reuse the shared score array for normalized softmax weights.

#include <metal_stdlib>
#include <metal_simdgroup>
using namespace metal;

constant int MAX_DECODE_POS = 128;

[[max_total_threads_per_threadgroup(256)]]
kernel void sdpa_decode_hd256(
  device const float *q       [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device const float *v_cache [[buffer(2)]],
  device float       *out     [[buffer(3)]],
  constant int &gqa_factor      [[buffer(4)]],
  constant int &n_pos           [[buffer(5)]],
  constant int &kv_head_stride  [[buffer(6)]],
  constant int &kv_seq_stride   [[buffer(7)]],
  constant float &scale         [[buffer(8)]],
  uint q_head [[threadgroup_position_in_grid]],
  uint tid    [[thread_position_in_threadgroup]],
  uint lane   [[thread_index_in_simdgroup]],
  uint simd   [[simdgroup_index_in_threadgroup]]
) {
  threadgroup float partial[8];
  threadgroup float scores[MAX_DECODE_POS];

  const int kv_head = int(q_head) / gqa_factor;
  const int q_off = int(q_head) * 256;
  const int kv_base = kv_head * kv_head_stride;
  const int usable_pos = min(n_pos, MAX_DECODE_POS);

  for (int p = 0; p < usable_pos; ++p) {
    float dot_part = q[q_off + int(tid)] *
      k_cache[kv_base + p * kv_seq_stride + int(tid)];
    float simd_part = simd_sum(dot_part);
    if (lane == 0) partial[simd] = simd_part;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (simd == 0) {
      float v = lane < 8 ? partial[lane] : 0.0f;
      float total = simd_sum(v);
      if (lane == 0) scores[p] = total * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }

  if (tid == 0) {
    float max_score = -INFINITY;
    for (int p = 0; p < usable_pos; ++p) max_score = max(max_score, scores[p]);
    float denom = 0.0f;
    for (int p = 0; p < usable_pos; ++p) {
      float e = fast::exp(scores[p] - max_score);
      scores[p] = e;
      denom += e;
    }
    float inv_denom = denom == 0.0f ? 0.0f : 1.0f / denom;
    for (int p = 0; p < usable_pos; ++p) scores[p] *= inv_denom;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  float result = 0.0f;
  for (int p = 0; p < usable_pos; ++p) {
    result += scores[p] * v_cache[kv_base + p * kv_seq_stride + int(tid)];
  }
  out[q_off + int(tid)] = result;
}
