#include <metal_stdlib>
using namespace metal;

constant int K_DIM_FC [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

kernel void silu_mul_packed_inplace_batch_fc(
  device float *gate [[buffer(0)]],
  device const float *up [[buffer(1)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i >= BATCH_FC * 8 * K_DIM_FC) return;

  float g = gate[i];
  gate[i] = (g / (1.0f + exp(-g))) * up[i];
}
