// attn_output_gate: per-element sigmoid + multiply.
//
//   out[i] = attn_out[i] * sigmoid(gate[i])
//
// qwen3.6 splits q_proj output [n_heads * head_dim * 2] into Q (used for
// attention) and a per-head gate (applied to attention output before o_proj).
// Both halves have the same layout — this kernel just elementwise-multiplies
// the SDPA output by sigmoid(gate).
//
// One thread per element. For qwen3.6 (n_heads=16 × head_dim=256) at decode:
// 4096 threads.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void attn_output_gate(
  device       float *__restrict__ attn_out [[buffer(0)]],   // [n] in-place
  device const float *__restrict__ gate     [[buffer(1)]],   // [n]
  constant int &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n) return;
  float g = gate[__tid];
  float s = 1.0f / (1.0f + exp(-g));   // sigmoid
  attn_out[__tid] = attn_out[__tid] * s;
}
