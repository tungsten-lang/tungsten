// Hyper-connection (gated residual) elementwise pieces. The two low-rank
// matvecs (10240->320 and 320->10240) and the tiny 10240->4 injection matvec
// run on the shared bf16_matvec kernel; these kernels supply the
// nonlinearities and stream reductions around them.
//
//   mix:     n   = grouped_rms_norm(H)                    (grouped_rms_norm.metal)
//            g   = silu( (W_down @ n) / hc )              (silu_div)
//            G_raw = W_up @ g                             (bf16_matvec)
//            x[i] = mean_s sigmoid(G_raw[s*d+i]) * n[s*d+i]   (hc_mix_reduce)
//   combine: inj_raw = W_inj @ n                          (bf16_matvec, 4 rows)
//            H[s*d+i] += y[i] * 2*sigmoid(inj_raw[s]/hc)  (hc_combine)

#include <metal_stdlib>
using namespace metal;

// x_out[i] = silu(x_in[i] / div). Dispatch: n threads.
[[max_total_threads_per_threadgroup(256)]]
kernel void silu_div(
  device const float *__restrict__ x_in  [[buffer(0)]],
  device       float *__restrict__ x_out [[buffer(1)]],
  constant float &div [[buffer(2)]],
  constant int   &n   [[buffer(3)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n) return;
  float v = x_in[__tid] / div;
  x_out[__tid] = v / (1.0f + exp(-v));
}

// x[i] = (1/S) * sum_s sigmoid(up_raw[s*d + i]) * n_in[s*d + i]
// Dispatch: d threads.
[[max_total_threads_per_threadgroup(256)]]
kernel void hc_mix_reduce(
  device const float *__restrict__ up_raw [[buffer(0)]],   // [S * d]
  device const float *__restrict__ n_in   [[buffer(1)]],   // [S * d]
  device       float *__restrict__ x      [[buffer(2)]],   // [d]
  constant int &S [[buffer(3)]],
  constant int &d [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= d) return;
  float acc = 0.0f;
  for (int s = 0; s < S; s++) {
    float g = 1.0f / (1.0f + exp(-up_raw[s * d + i]));
    acc += g * n_in[s * d + i];
  }
  x[i] = acc / float(S);
}

// H[s*d + i] += y[i] * 2*sigmoid(inj_raw[s] / S). Dispatch: S*d threads.
[[max_total_threads_per_threadgroup(256)]]
kernel void hc_combine(
  device       float *__restrict__ H       [[buffer(0)]],  // [S * d], in place
  device const float *__restrict__ y       [[buffer(1)]],  // [d]
  device const float *__restrict__ inj_raw [[buffer(2)]],  // [S]
  constant int &S [[buffer(3)]],
  constant int &d [[buffer(4)]],
  uint __tid [[thread_position_in_grid]]
) {
  int t = int(__tid);
  if (t >= S * d) return;
  int s = t / d;
  int i = t % d;
  float w = 2.0f / (1.0f + exp(-inj_raw[s] / float(S)));
  H[t] += y[i] * w;
}
