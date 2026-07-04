#include <metal_stdlib>
using namespace metal;

constant int N_ROWS_FC [[function_constant(0)]];

kernel void moe_combine_8_packed_residual_fc(
  device float *x [[buffer(0)]],
  device const float *eo [[buffer(1)]],
  device const float *weights [[buffer(2)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i >= N_ROWS_FC) return;
  float acc = 0.0f;
  for (int slot = 0; slot < 8; slot++) {
    acc += weights[slot] * eo[slot * N_ROWS_FC + i];
  }
  x[i] += acc;
}
