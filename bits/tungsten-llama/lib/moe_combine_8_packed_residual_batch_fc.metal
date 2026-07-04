#include <metal_stdlib>
using namespace metal;

constant int N_ROWS_FC [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

kernel void moe_combine_8_packed_residual_batch_fc(
  device float *x [[buffer(0)]],
  device const float *eo [[buffer(1)]],
  device const float *weights [[buffer(2)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid) % N_ROWS_FC;
  int token = int(tid) / N_ROWS_FC;
  if (token >= BATCH_FC) return;

  float acc = 0.0f;
  int eo_base = token * 8 * N_ROWS_FC;
  int w_base = token * 8;
  for (int slot = 0; slot < 8; slot++) {
    acc += weights[w_base + slot] * eo[eo_base + slot * N_ROWS_FC + i];
  }
  x[token * N_ROWS_FC + i] += acc;
}
