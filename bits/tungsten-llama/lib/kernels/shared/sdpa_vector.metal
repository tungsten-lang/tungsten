// Fused attention for decode (M=1) — port of MLX's sdpa_vector.
// One TG per Q head, 32 simdgroups × 32 lanes = 1024 threads.
// Each simdgroup processes one K position per loop iter (stride BN=32).
// Each lane within a simdgroup handles HEAD_DIM/BD=4 values of qk_per_thread.
// Online softmax — no scratch scores buffer.
//
// Dispatch: N_Q_HEADS TGs of 1024 threads. (For decode where q_seq=1.)
//
// HEAD_DIM = 128, BN = 32, BD = 32 → qk_per_thread = v_per_thread = 4.
// K cache layout: [pos × N_KV_HEADS × HEAD_DIM]   (KV_ROW = N_KV_HEADS * HEAD_DIM)
// V cache layout: same
// Q layout:        [N_Q_HEADS × HEAD_DIM]
// Output layout:   [N_Q_HEADS × HEAD_DIM]

#include <metal_stdlib>
#include <metal_simdgroup>
using namespace metal;

[[max_total_threads_per_threadgroup(1024)]]
kernel void sdpa_vector(
  device const float *q       [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device const float *v_cache [[buffer(2)]],
  device float       *out     [[buffer(3)]],
  constant int &gqa_factor   [[buffer(4)]],   // N_Q_HEADS / N_KV_HEADS
  constant int &n_pos        [[buffer(5)]],   // active KV positions
  constant int &kv_head_stride [[buffer(6)]], // = HEAD_DIM (since cache is [pos][head][dim])
  constant int &kv_seq_stride  [[buffer(7)]], // = N_KV_HEADS * HEAD_DIM = KV_ROW
  constant float &scale       [[buffer(8)]],
  uint3 tid       [[threadgroup_position_in_grid]],
  uint3 tpg       [[threadgroups_per_grid]],
  uint  simd_gid  [[simdgroup_index_in_threadgroup]],
  uint  simd_lid  [[thread_index_in_simdgroup]]
) {
  const int HEAD_DIM = 128;
  const int BN = 32;
  const int BD = 32;
  const int qk_per_thread = HEAD_DIM / BD;  // 4
  const int v_per_thread  = HEAD_DIM / BD;  // 4

  const int q_head_idx = int(tid.x);
  const int kv_head_idx = q_head_idx / gqa_factor;

  // Per-thread registers
  thread float q_reg[4];
  thread float k_reg[4];
  thread float o_reg[4] = {0.0f, 0.0f, 0.0f, 0.0f};

  // Threadgroup memory for cross-simdgroup combine
  threadgroup float outputs[BN * BD];   // 1024 floats = 4 KB
  threadgroup float max_scores[BN];     // 32 floats = 128 B
  threadgroup float sum_exp_scores[BN]; // 32 floats = 128 B

  // Load Q for this head into registers (each lane gets HEAD_DIM/BD = 4 elements).
  // Q layout: q[q_head * HEAD_DIM + i]
  device const float *q_ptr = q + q_head_idx * HEAD_DIM + simd_lid * qk_per_thread;
  for (int i = 0; i < qk_per_thread; i++) {
    q_reg[i] = scale * q_ptr[i];
  }

  // Online softmax accumulators (per-lane / per-simdgroup)
  float max_score = -1.0e30f;
  float sum_exp_score = 0.0f;

  // Each simdgroup handles K positions strided by BN=32, starting at simd_gid.
  // Per K position: read K vector (cooperative across lanes), compute Q·K (simd_sum),
  // update online softmax max/sum, accumulate into o_reg.
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

  // Cross-simdgroup combine: each simdgroup has a partial (o_reg, max_score, sum_exp_score).
  // Merge them via online-softmax aggregation.
  if (simd_lid == 0) {
    max_scores[simd_gid] = max_score;
    sum_exp_scores[simd_gid] = sum_exp_score;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Each lane reads the BN max/sum values, finds global max, and computes scaled sum.
  float ms = max_scores[simd_lid];
  float new_max = simd_max(ms);
  float factor = fast::exp(ms - new_max);
  sum_exp_score = simd_sum(sum_exp_scores[simd_lid] * factor);

  // Aggregate per-element outputs across simdgroups.
  for (int i = 0; i < v_per_thread; i++) {
    outputs[simd_lid * BD + simd_gid] = o_reg[i];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    o_reg[i] = simd_sum(outputs[simd_gid * BD + simd_lid] * factor);
    if (sum_exp_score != 0.0f) {
      o_reg[i] = o_reg[i] / sum_exp_score;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }

  // Write the output: lane 0 of each simdgroup writes v_per_thread elements at offset simd_gid * v_per_thread.
  // Output layout: out[q_head * HEAD_DIM + i]
  if (simd_lid == 0) {
    device float *out_ptr = out + q_head_idx * HEAD_DIM + simd_gid * v_per_thread;
    for (int i = 0; i < v_per_thread; i++) {
      out_ptr[i] = o_reg[i];
    }
  }
}
