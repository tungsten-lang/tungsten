#include <metal_stdlib>
using namespace metal;

constant int N_EXPERTS_FC [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

kernel void router_topk_8_packed_batch_fc(
  device const float *scores [[buffer(0)]],
  device int *selected [[buffer(1)]],
  device float *weights [[buffer(2)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg);
  if (token >= BATCH_FC || lane != 0) return;

  float local[128];
  int score_base = token * N_EXPERTS_FC;
  for (int i = 0; i < N_EXPERTS_FC; i++) local[i] = scores[score_base + i];

  int best_i[8];
  float best_v[8];
  for (int k = 0; k < 8; k++) {
    float bv = -1.0e30f;
    int bi = -1;
    for (int j = 0; j < N_EXPERTS_FC; j++) {
      if (local[j] > bv) { bv = local[j]; bi = j; }
    }
    best_i[k] = bi;
    best_v[k] = bv;
    local[bi] = -1.0e30f;
  }

  float max_v = best_v[0];
  float sum_e = 0.0f;
  float exps[8];
  for (int k = 0; k < 8; k++) {
    exps[k] = exp(best_v[k] - max_v);
    sum_e += exps[k];
  }
  float inv_s = 1.0f / sum_e;
  int out_base = token * 8;
  for (int k = 0; k < 8; k++) {
    selected[out_base + k] = best_i[k];
    weights[out_base + k] = exps[k] * inv_s;
  }
}
