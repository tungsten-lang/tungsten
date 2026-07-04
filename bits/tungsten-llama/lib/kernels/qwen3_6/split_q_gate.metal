// split_q_gate: extract per-head Q and gate halves from a stacked q_proj output.
//
// qwen3.6's `attn_output_gate=true` makes q_proj produce 2× the natural width:
// `[n_heads, head_dim * 2]` per token, where for each head the first head_dim
// elements are the query and the next head_dim are the gate (later applied as
// sigmoid(gate) × attn_output before o_proj).
//
// This kernel splits that stacked layout into two contiguous tensors:
//   queries[h, i] = q_full[h * (head_dim*2) + i]
//   gate[h, i]    = q_full[h * (head_dim*2) + head_dim + i]
//
// One thread per output element. For qwen3.6 (n_heads=16 × head_dim=256):
// 4096 threads.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void split_q_gate(
  device const float *__restrict__ q_full [[buffer(0)]],   // [n_heads * head_dim * 2]
  device       float *__restrict__ queries [[buffer(1)]],  // [n_heads * head_dim]
  device       float *__restrict__ gate    [[buffer(2)]],  // [n_heads * head_dim]
  constant int &n_heads  [[buffer(3)]],
  constant int &head_dim [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int n = n_heads * head_dim;
  if (int(__tid) >= n) return;
  int h = int(__tid) / head_dim;
  int i = int(__tid) % head_dim;
  int two_d = head_dim * 2;
  queries[h * head_dim + i] = q_full[h * two_d + i];
  gate[h * head_dim + i]    = q_full[h * two_d + head_dim + i];
}
