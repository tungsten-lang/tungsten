#include <metal_stdlib>
using namespace metal;

constant int K_DIM_FC [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC [[function_constant(2)]];

[[max_total_threads_per_threadgroup(32)]]
kernel void f32_matvec_batch_fc(
  device const float *w [[buffer(0)]],
  device const float *x [[buffer(1)]],
  device float *y [[buffer(2)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg) / N_ROWS_FC;
  int m = int(tg) - token * N_ROWS_FC;
  if (token >= BATCH_FC) return;

  int x_base = token * K_DIM_FC;
  float partial = 0.0f;
  for (int i = int(lane); i < K_DIM_FC; i += 32) {
    partial += w[m * K_DIM_FC + i] * x[x_base + i];
  }
  float total = simd_sum(partial);
  if (lane == 0) y[token * N_ROWS_FC + m] = total;
}
