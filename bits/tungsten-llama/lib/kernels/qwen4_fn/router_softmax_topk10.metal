// Fused router softmax + top-10 selection + score renormalization for
// Qwen4Exp MoE (512 experts, softmax FIRST over all 512, then top-k over
// probabilities, then renormalize the chosen 10 — norm_topk_prob=true).
//
// Same structure as qwen3_6/router_softmax_topk8.metal at N=512, K=10.
//
// Dispatch: ONE TG of 512 threads.

#include <metal_stdlib>
using namespace metal;

constant int N = 512;
constant int K = 10;

[[max_total_threads_per_threadgroup(512)]]
kernel void router_softmax_topk10(
  device const float *logits      [[buffer(0)]],
  device int         *top_indices [[buffer(1)]],
  device float       *top_scores  [[buffer(2)]],
  uint __tid [[thread_position_in_threadgroup]]
) {
  threadgroup float reduce_vals[N];
  threadgroup int   reduce_ids[N];
  threadgroup float probs[N];
  threadgroup float chosen_scores[K];
  threadgroup int   chosen_ids[K];
  threadgroup float scratch_sum[1];

  int tid = int(__tid);
  float my_logit = logits[tid];

  // ---- 1. max ----
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

  // ---- 2. sum of exp ----
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

  float my_prob = my_exp / sum_exp;
  probs[tid] = my_prob;
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // ---- 3. K x argmax-then-mask. Ties resolve to the LOWEST index, matching
  // torch.topk's first-occurrence order (>' strictly, scanning keeps tid). ----
  for (int k = 0; k < K; k++) {
    reduce_vals[tid] = probs[tid];
    reduce_ids[tid]  = tid;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (int stride = N / 2; stride > 0; stride >>= 1) {
      if (tid < stride) {
        bool take = (reduce_vals[tid + stride] > reduce_vals[tid]) ||
                    (reduce_vals[tid + stride] == reduce_vals[tid] &&
                     reduce_ids[tid + stride] < reduce_ids[tid]);
        if (take) {
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
    if (tid == chosen_ids[k]) {
      probs[tid] = -1.0e30f;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }

  // ---- 4. renormalize the chosen K ----
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
