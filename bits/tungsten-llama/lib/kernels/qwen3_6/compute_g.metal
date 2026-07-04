// compute_g: Mamba/SSM decay coefficient.
//
//   g[b, t, hv] = exp(-exp(A_log[hv]) * softplus(a[b,t,hv] + dt_bias[hv]))
//
// where softplus(x) = log(1 + exp(x)).
//
// One thread per (b, t, hv) element. For qwen3.6 decode (B=1, T=1, Hv=32):
// 32 threads. Tiny kernel — included for bit-exact match against MLX rather
// than perf.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void compute_g(
  device const float *__restrict__ a       [[buffer(0)]],   // [B, T, Hv]
  device const float *__restrict__ A_log   [[buffer(1)]],   // [Hv]
  device const float *__restrict__ dt_bias [[buffer(2)]],   // [Hv]
  device       float *__restrict__ g       [[buffer(3)]],   // [B, T, Hv]
  constant int &Hv [[buffer(4)]],
  constant int &n_total [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n_total) return;
  int hv_idx = int(__tid) % Hv;
  float a_val = a[__tid] + dt_bias[hv_idx];
  float sp = log(1.0f + exp(a_val));        // softplus
  float A = exp(A_log[hv_idx]);
  g[__tid] = exp(-A * sp);
}
