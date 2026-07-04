#include <metal_stdlib>
using namespace metal;

kernel void moe_combine_8_packed_residual(
  device float *x [[buffer(0)]],
  device const float *eo [[buffer(1)]],
  device const float *weights [[buffer(2)]],
  constant int &n_rows [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i >= n_rows) return;
  float acc = 0.0f;
  for (int slot = 0; slot < 8; slot++) {
    acc += weights[slot] * eo[slot * n_rows + i];
  }
  x[i] += acc;
}
