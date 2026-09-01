// MoE output assembly for Qwen4Exp.
//
//   moe_weighted_sum:  y[i] = sum_k w[k] * d[k * n + i]
//     (top-K routed expert down-proj outputs, router weights on device)
//   moe_shared_combine: out[i] = routed[i] + sigmoid(gate_raw[0]) * shared[i]
//     (always-on shared expert with a scalar sigmoid gate; gate_raw is the
//      1-row bf16_matvec output of shared_expert_gate)
//
// Dispatch: n threads each.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void moe_weighted_sum(
  device const float *__restrict__ d [[buffer(0)]],   // [K, n]
  device const float *__restrict__ w [[buffer(1)]],   // [K]
  device       float *__restrict__ y [[buffer(2)]],   // [n]
  constant int &K [[buffer(3)]],
  constant int &n [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= n) return;
  float acc = 0.0f;
  for (int k = 0; k < K; k++) {
    acc += w[k] * d[k * n + i];
  }
  y[i] = acc;
}

// Routing histogram: hist[layer*512 + top_idx[k]] += 1. The 10 selected
// indices are distinct and layers write disjoint slots, so no atomics are
// needed under the engine's per-token command-buffer ordering.
[[max_total_threads_per_threadgroup(32)]]
kernel void expert_hist_accum(
  device const int  *__restrict__ top_idx [[buffer(0)]],
  device uint       *__restrict__ hist    [[buffer(1)]],
  constant int &layer [[buffer(2)]],
  constant int &K     [[buffer(3)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= K) return;
  hist[layer * 512 + top_idx[__tid]] += 1;
}

[[max_total_threads_per_threadgroup(256)]]
kernel void moe_shared_combine(
  device const float *__restrict__ routed   [[buffer(0)]],  // [n]
  device const float *__restrict__ shared_y [[buffer(1)]],  // [n]
  device const float *__restrict__ gate_raw [[buffer(2)]],  // [1]
  device       float *__restrict__ out      [[buffer(3)]],  // [n]
  constant int &n [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= n) return;
  float g = 1.0f / (1.0f + exp(-gate_raw[0]));
  out[i] = routed[i] + g * shared_y[i];
}
