#include <metal_stdlib>
using namespace metal;

constant int N_FC     [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

kernel void rms_norm_batch_fc(
  device const float *x [[buffer(0)]],
  device const float *w [[buffer(1)]],
  device float *y [[buffer(2)]],
  constant float &inv_n [[buffer(3)]],
  constant float &eps [[buffer(4)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg);
  if (token >= BATCH_FC) return;

  int base = token * N_FC;
  float sum_sq = 0.0f;
  for (int i = int(lane); i < N_FC; i += 32) {
    float v = x[base + i];
    sum_sq += v * v;
  }
  float total = simd_sum(sum_sq);
  float rrms = 1.0f / sqrt(total * inv_n + eps);
  for (int i = int(lane); i < N_FC; i += 32) {
    y[base + i] = x[base + i] * rrms * w[i];
  }
}
