// Fused router matvec + top-K + softmax. Replaces the sequence:
//     f32_matvec(router_w, xn) → router_scores
//     barrier
//     router_topk_8(router_scores, ...) → selected_ids + weights
// with a single dispatch that does both, sharing the 128-element
// scores via threadgroup memory. Eliminates 1 barrier and 1 dispatch
// per layer × 48 = 96/token.
//
// Decomposition: 1 threadgroup with 32 simdgroups × 32 lanes = 1024
// threads. Each simdgroup computes 4 router output rows (32 sg × 4
// = 128 = N_EXPERTS). Within a simdgroup, 32 lanes cooperate via
// simd_sum on the dot product.
//
// Phase 1: 32 simdgroups parallel compute scores into tg_scores[128]
// Phase 2: simdgroup 0 lane 0 does top-8 + softmax over the 128
//          scores, writes selected_ids and weights.

#include <metal_stdlib>
using namespace metal;

kernel void router_matvec_topk_8(
  device float *router_w [[buffer(0)]],   // [N_EXPERTS, HIDDEN]
  device float *xn       [[buffer(1)]],   // [HIDDEN]
  device int   *sel0     [[buffer(2)]],
  device int   *sel1     [[buffer(3)]],
  device int   *sel2     [[buffer(4)]],
  device int   *sel3     [[buffer(5)]],
  device int   *sel4     [[buffer(6)]],
  device int   *sel5     [[buffer(7)]],
  device int   *sel6     [[buffer(8)]],
  device int   *sel7     [[buffer(9)]],
  device float *weights  [[buffer(10)]],
  constant int &n_experts [[buffer(11)]],  // 128
  constant int &hidden    [[buffer(12)]],  // 2048
  threadgroup float *tg_scores [[threadgroup(0)]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]]
) {
  int sg = int(__simd_id);
  int lane = int(__simd_lane);

  // Phase 1: each simdgroup computes 4 router output rows
  for (int o = 0; o < 4; o++) {
    int row = sg * 4 + o;
    if (row < n_experts) {
      float partial = 0.0f;
      for (int i = lane; i < hidden; i += 32) {
        partial += router_w[row * hidden + i] * xn[i];
      }
      float total = simd_sum(partial);
      if (lane == 0) tg_scores[row] = total;
    }
  }

  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Phase 2: top-8 + softmax in simdgroup 0 lane 0
  if (sg == 0 && lane == 0) {
    float scores_local[128];
    for (int i = 0; i < n_experts; i++) scores_local[i] = tg_scores[i];

    int best_i[8];
    float best_v[8];
    for (int k = 0; k < 8; k++) {
      float bv = -1e30f;
      int bi = -1;
      for (int j = 0; j < n_experts; j++) {
        if (scores_local[j] > bv) { bv = scores_local[j]; bi = j; }
      }
      best_v[k] = bv;
      best_i[k] = bi;
      scores_local[bi] = -1e30f;
    }

    float max_v = best_v[0];
    float sum_e = 0.0f;
    float exps[8];
    for (int k = 0; k < 8; k++) {
      exps[k] = exp(best_v[k] - max_v);
      sum_e += exps[k];
    }
    float inv_s = 1.0f / sum_e;

    sel0[0] = best_i[0];
    sel1[0] = best_i[1];
    sel2[0] = best_i[2];
    sel3[0] = best_i[3];
    sel4[0] = best_i[4];
    sel5[0] = best_i[5];
    sel6[0] = best_i[6];
    sel7[0] = best_i[7];

    for (int k = 0; k < 8; k++) weights[k] = exps[k] * inv_s;
  }
}
