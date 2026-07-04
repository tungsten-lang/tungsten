// Sigmoid: y[i] = 1/(1+exp(-x[i])).
// Used in qwen3.6 Mamba's beta = sigmoid(b) computation (HV=32 elements)
// to avoid a CPU readback round-trip between batches.

#include <metal_stdlib>
using namespace metal;

kernel void sigmoid_f32(
  device const float *x [[buffer(0)]],
  device float       *y [[buffer(1)]],
  constant int       &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]]
) {
  int tid = int(__tid);
  if (tid >= n) return;
  y[tid] = 1.0f / (1.0f + exp(-x[tid]));
}
