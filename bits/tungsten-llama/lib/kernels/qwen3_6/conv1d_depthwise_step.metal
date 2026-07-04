// conv1d_depthwise_step: causal 1D depthwise conv, kernel_size=4, single time step.
//
// For decode (T=1) this collapses to a 4-tap dot product per channel:
//   out[c] = sum_k weight[c, k, 0] * input_seq[k, c]
// where input_seq = concat(state[0..2, c], current_input[c]).
//
// Then silu(out) is applied (Mamba uses fused conv→silu).
//
// State is updated to slide left:
//   new_state = [state[1], state[2], current_input]
// (The kernel writes the new state in-place via state_out, then the host
//  rotates the pointer.)
//
// Layout:
//   weight:  [C, kernel=4, 1]   row-major; for channel c, taps at [c, 0..3, 0]
//   state:   [B, kernel-1=3, C] row-major; older steps first
//   x:       [B, T=1, C]        new step
//   out:     [B, T=1, C]        silu(conv result)
//   state_out: [B, kernel-1=3, C]  = [state[1], state[2], x] sliding window
//
// One thread per (b, channel). For qwen3.6: B=1, C=8192 → 8192 threads.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void conv1d_depthwise_step(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [B, 3, C]
  device const float *__restrict__ x         [[buffer(2)]],   // [B, 1, C]
  device       float *__restrict__ out       [[buffer(3)]],   // [B, 1, C]
  device       float *__restrict__ state_out [[buffer(4)]],   // [B, 3, C]
  constant int &C [[buffer(5)]],
  constant int &n_total [[buffer(6)]],     // = B * C
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n_total) return;
  int b_idx = int(__tid) / C;
  int c     = int(__tid) % C;

  // Pull this channel's 3 state entries + new x.
  float s0 = state[(b_idx * 3 + 0) * C + c];
  float s1 = state[(b_idx * 3 + 1) * C + c];
  float s2 = state[(b_idx * 3 + 2) * C + c];
  float x_new = x[b_idx * C + c];

  // 4-tap dot product. weight[c, k, 0] = weight[c * 4 + k] (kernel last-dim is 1).
  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  float conv_out = w0 * s0 + w1 * s1 + w2 * s2 + w3 * x_new;

  // silu(conv_out) = conv_out * sigmoid(conv_out)
  float sig = 1.0f / (1.0f + exp(-conv_out));
  out[b_idx * C + c] = conv_out * sig;

  // Slide state: new = [s1, s2, x_new]
  state_out[(b_idx * 3 + 0) * C + c] = s1;
  state_out[(b_idx * 3 + 1) * C + c] = s2;
  state_out[(b_idx * 3 + 2) * C + c] = x_new;
}
