#include <metal_stdlib>
using namespace metal;

constant int N_EXPERTS_FC [[function_constant(0)]];

kernel void router_topk_8_packed_fc(
  device float *scores [[buffer(0)]],
  device int *selected [[buffer(1)]],
  device float *weights [[buffer(2)]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  if (__simd_lane != 0) return;

  float local[128];
  for (int i = 0; i < N_EXPERTS_FC; i++) local[i] = scores[i];

  int best_i[8];
  float best_v[8];
  for (int k = 0; k < 8; k++) {
    float bv = -1e30f;
    int bi = -1;
    for (int j = 0; j < N_EXPERTS_FC; j++) {
      if (local[j] > bv) { bv = local[j]; bi = j; }
    }
    best_i[k] = bi;
    best_v[k] = bv;
    local[bi] = -1e30f;
  }

  float max_v = best_v[0];
  float sum_e = 0.0f;
  float exps[8];
  for (int k = 0; k < 8; k++) {
    exps[k] = exp(best_v[k] - max_v);
    sum_e += exps[k];
  }
  float inv_s = 1.0f / sum_e;

  for (int k = 0; k < 8; k++) {
    selected[k] = best_i[k];
    weights[k] = exps[k] * inv_s;
  }
}
