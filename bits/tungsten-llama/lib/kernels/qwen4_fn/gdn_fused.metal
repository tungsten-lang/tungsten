// Dispatch-count fusions for the GDN chain and MoE tail (decode is ~2300
// dispatches/token; each removed per-layer dispatch is worth ~0.25ms/token).
//
//   gdn_conv_split: conv1d_depthwise_step + the three split copies in one —
//     writes silu(conv) directly into the q/k/v slices and slides the state.
//   gdn_g_beta: compute_g + sigmoid(beta) in one tiny dispatch.
//   moe_output: weighted expert sum + sigmoid-gated shared expert add.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void gdn_conv_split(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [3, C] older first
  device const float *__restrict__ x         [[buffer(2)]],   // [C]
  device       float *__restrict__ q_out     [[buffer(3)]],   // [q_dim]
  device       float *__restrict__ k_out     [[buffer(4)]],   // [k_dim]
  device       float *__restrict__ v_out     [[buffer(5)]],   // [v_dim]
  device       float *__restrict__ state_out [[buffer(6)]],   // [3, C]
  constant int &C     [[buffer(7)]],
  constant int &q_dim [[buffer(8)]],
  constant int &k_dim [[buffer(9)]],
  uint __tid [[thread_position_in_grid]]
) {
  int c = int(__tid);
  if (c >= C) return;

  float s0 = state[0 * C + c];
  float s1 = state[1 * C + c];
  float s2 = state[2 * C + c];
  float x_new = x[c];

  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  float conv_out = w0 * s0 + w1 * s1 + w2 * s2 + w3 * x_new;
  float sig = 1.0f / (1.0f + exp(-conv_out));
  float y = conv_out * sig;

  if (c < q_dim) {
    q_out[c] = y;
  } else if (c < q_dim + k_dim) {
    k_out[c - q_dim] = y;
  } else {
    v_out[c - q_dim - k_dim] = y;
  }

  state_out[0 * C + c] = s1;
  state_out[1 * C + c] = s2;
  state_out[2 * C + c] = x_new;
}

[[max_total_threads_per_threadgroup(64)]]
kernel void gdn_g_beta(
  device const float *__restrict__ a       [[buffer(0)]],   // [Hv]
  device const float *__restrict__ b       [[buffer(1)]],   // [Hv]
  device const float *__restrict__ A_log   [[buffer(2)]],   // [Hv]
  device const float *__restrict__ dt_bias [[buffer(3)]],   // [Hv]
  device       float *__restrict__ g       [[buffer(4)]],   // [Hv]
  device       float *__restrict__ beta    [[buffer(5)]],   // [Hv]
  constant int &Hv [[buffer(6)]],
  uint __tid [[thread_position_in_grid]]
) {
  int h = int(__tid);
  if (h >= Hv) return;
  float a_val = a[h] + dt_bias[h];
  float sp = log(1.0f + exp(a_val));
  g[h] = exp(-exp(A_log[h]) * sp);
  beta[h] = 1.0f / (1.0f + exp(-b[h]));
}

[[max_total_threads_per_threadgroup(256)]]
kernel void moe_output(
  device const float *__restrict__ d        [[buffer(0)]],  // [K, n] expert down outs
  device const float *__restrict__ w        [[buffer(1)]],  // [K] router weights
  device const float *__restrict__ shared_y [[buffer(2)]],  // [n]
  device const float *__restrict__ gate_raw [[buffer(3)]],  // [1]
  device       float *__restrict__ y        [[buffer(4)]],  // [n]
  constant int &K [[buffer(5)]],
  constant int &n [[buffer(6)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= n) return;
  float acc = 0.0f;
  for (int k = 0; k < K; k++) {
    acc += w[k] * d[k * n + i];
  }
  float g = 1.0f / (1.0f + exp(-gate_raw[0]));
  y[i] = acc + g * shared_y[i];
}
