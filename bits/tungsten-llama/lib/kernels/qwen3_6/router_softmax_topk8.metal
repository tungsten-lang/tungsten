// Fused router softmax + top-8 selection + score normalization for qwen3.6 MoE.
//
// Replaces the per-MoE-step CPU sequence:
//   read 256 router logits
//   subtract max + exp + accumulate sum
//   normalize: prob = exp / sum
//   8 iterations of (find max, mark taken)
//   normalize top-8 scores so they sum to 1
//
// Inputs:
//   router_logits[256]  raw int8-affine matvec output
// Outputs:
//   top_indices[8]      i32 expert ids, ordered high → low score
//   top_scores[8]       f32 normalized scores (sum = 1)
//
// Dispatch: ONE TG of 256 threads.

#include <metal_stdlib>
using namespace metal;

constant int N = 256;
constant int K = 8;

[[max_total_threads_per_threadgroup(256)]]
kernel void router_softmax_topk8(
  device const float *logits      [[buffer(0)]],
  device int         *top_indices [[buffer(1)]],
  device float       *top_scores  [[buffer(2)]],
  uint __tid [[thread_position_in_threadgroup]]
) {
  // Threadgroup-scope scratch (must be declared at function scope in Metal).
  threadgroup float reduce_vals[N];
  threadgroup int   reduce_ids[N];
  threadgroup float probs[N];
  threadgroup float chosen_scores[K];
  threadgroup int   chosen_ids[K];
  threadgroup float scratch_sum[1];

  int tid = int(__tid);
  float my_logit = logits[tid];

  // ---- 1. Find max via tree reduction ----
  reduce_vals[tid] = my_logit;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int stride = N / 2; stride > 0; stride >>= 1) {
    if (tid < stride) {
      reduce_vals[tid] = max(reduce_vals[tid], reduce_vals[tid + stride]);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  float max_logit = reduce_vals[0];
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // ---- 2. Compute exp(logit - max), then sum ----
  float my_exp = exp(my_logit - max_logit);
  reduce_vals[tid] = my_exp;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int stride = N / 2; stride > 0; stride >>= 1) {
    if (tid < stride) {
      reduce_vals[tid] = reduce_vals[tid] + reduce_vals[tid + stride];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  float sum_exp = reduce_vals[0];
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // ---- 3. Each thread holds its prob, also stored in shared probs[] ----
  float my_prob = my_exp / sum_exp;
  probs[tid] = my_prob;
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // ---- 4. K iterations of argmax-then-mask ----
  for (int k = 0; k < K; k++) {
    reduce_vals[tid] = probs[tid];
    reduce_ids[tid]  = tid;
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (int stride = N / 2; stride > 0; stride >>= 1) {
      if (tid < stride) {
        if (reduce_vals[tid + stride] > reduce_vals[tid]) {
          reduce_vals[tid] = reduce_vals[tid + stride];
          reduce_ids[tid]  = reduce_ids[tid + stride];
        }
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
      chosen_scores[k] = reduce_vals[0];
      chosen_ids[k]    = reduce_ids[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Mark winner so it won't be picked again
    if (tid == chosen_ids[k]) {
      probs[tid] = -1.0e30f;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }

  // ---- 5. Normalize top-K scores (matches MLX norm_topk_prob=true) ----
  if (tid == 0) {
    float s = 0.0f;
    for (int k = 0; k < K; k++) s += chosen_scores[k];
    scratch_sum[0] = s;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  if (tid < K) {
    top_indices[tid] = chosen_ids[tid];
    top_scores[tid]  = chosen_scores[tid] / scratch_sum[0];
  }
}
