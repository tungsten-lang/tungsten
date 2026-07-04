// sdpa_vector for qwen3.6's head_dim=256.
//
// Copy of sdpa_vector.metal (f32 KV) with HEAD_DIM bumped from 128 to 256.
// Per-lane register tiles double from 4 to 8 floats.
//
// Same TG shape: 1024 threads (32 simdgroups × 32 lanes).
// Per K position: each lane loads its 8-element register tile, runs the
// f32 dot/online-softmax pipeline.

#include <metal_stdlib>
#include <metal_simdgroup>
using namespace metal;

[[max_total_threads_per_threadgroup(1024)]]
kernel void sdpa_vector_hd256(
  device const float *q       [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device const float *v_cache [[buffer(2)]],
  device float       *out     [[buffer(3)]],
  constant int &gqa_factor   [[buffer(4)]],
  constant int &n_pos        [[buffer(5)]],
  constant int &kv_head_stride [[buffer(6)]],
  constant int &kv_seq_stride  [[buffer(7)]],
  constant float &scale       [[buffer(8)]],
  uint3 tid       [[threadgroup_position_in_grid]],
  uint3 tpg       [[threadgroups_per_grid]],
  uint  simd_gid  [[simdgroup_index_in_threadgroup]],
  uint  simd_lid  [[thread_index_in_simdgroup]]
) {
  const int HEAD_DIM = 256;
  const int BN = 32;
  const int BD = 32;
  const int qk_per_thread = HEAD_DIM / BD;   // 8
  const int v_per_thread  = HEAD_DIM / BD;   // 8

  const int q_head_idx = int(tid.x);
  const int kv_head_idx = q_head_idx / gqa_factor;

  thread float q_reg[8];
  thread float k_reg[8];
  thread float o_reg[8] = {0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0f};

  threadgroup float outputs[BN * BD];
  threadgroup float max_scores[BN];
  threadgroup float sum_exp_scores[BN];

  device const float *q_ptr = q + q_head_idx * HEAD_DIM + simd_lid * qk_per_thread;
  for (int i = 0; i < qk_per_thread; i++) {
    q_reg[i] = scale * q_ptr[i];
  }

  float max_score = -1.0e30f;
  float sum_exp_score = 0.0f;

  device const float *k_ptr_base = k_cache + kv_head_idx * kv_head_stride + simd_lid * qk_per_thread;
  device const float *v_ptr_base = v_cache + kv_head_idx * kv_head_stride + simd_lid * v_per_thread;

  int kv_pos = int(simd_gid);
  while (kv_pos < n_pos) {
    device const float *k_ptr = k_ptr_base + kv_pos * kv_seq_stride;
    device const float *v_ptr = v_ptr_base + kv_pos * kv_seq_stride;

    for (int j = 0; j < qk_per_thread; j++) {
      k_reg[j] = k_ptr[j];
    }

    float score = 0.0f;
    for (int j = 0; j < qk_per_thread; j++) {
      score += q_reg[j] * k_reg[j];
    }
    score = simd_sum(score);

    float new_max = max(max_score, score);
    float factor = fast::exp(max_score - new_max);
    float exp_score = fast::exp(score - new_max);
    max_score = new_max;
    sum_exp_score = sum_exp_score * factor + exp_score;

    for (int j = 0; j < v_per_thread; j++) {
      o_reg[j] = o_reg[j] * factor + exp_score * v_ptr[j];
    }

    kv_pos += BN;
  }

  if (simd_lid == 0) {
    max_scores[simd_gid] = max_score;
    sum_exp_scores[simd_gid] = sum_exp_score;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  float ms = max_scores[simd_lid];
  float new_max = simd_max(ms);
  float factor = fast::exp(ms - new_max);
  sum_exp_score = simd_sum(sum_exp_scores[simd_lid] * factor);

  for (int i = 0; i < v_per_thread; i++) {
    outputs[simd_lid * BD + simd_gid] = o_reg[i];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    o_reg[i] = simd_sum(outputs[simd_gid * BD + simd_lid] * factor);
    if (sum_exp_score != 0.0f) {
      o_reg[i] = o_reg[i] / sum_exp_score;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }

  if (simd_lid == 0) {
    device float *out_ptr = out + q_head_idx * HEAD_DIM + simd_gid * v_per_thread;
    for (int i = 0; i < v_per_thread; i++) {
      out_ptr[i] = o_reg[i];
    }
  }
}
