// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void router_topk_8(
  device float *scores [[buffer(0)]],
  device int *sel0 [[buffer(1)]],
  device int *sel1 [[buffer(2)]],
  device int *sel2 [[buffer(3)]],
  device int *sel3 [[buffer(4)]],
  device int *sel4 [[buffer(5)]],
  device int *sel5 [[buffer(6)]],
  device int *sel6 [[buffer(7)]],
  device int *sel7 [[buffer(8)]],
  device float *weights [[buffer(9)]],
  constant int &n_experts [[buffer(10)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int lane = int(__simd_lane);
  if ((lane == 0)) {
    int i = 0;
    while ((i < 8)) {
      float best_v = -1000000000.0f;
      int best_i = -(1);
      int j = 0;
      while ((j < n_experts)) {
        float v = scores[j];
        if ((v > best_v)) {
          best_v = v;
          best_i = j;
        }
        j = (j + 1);
      }
      if ((i == 0)) {
        sel0[0] = best_i;
      }
      if ((i == 1)) {
        sel1[0] = best_i;
      }
      if ((i == 2)) {
        sel2[0] = best_i;
      }
      if ((i == 3)) {
        sel3[0] = best_i;
      }
      if ((i == 4)) {
        sel4[0] = best_i;
      }
      if ((i == 5)) {
        sel5[0] = best_i;
      }
      if ((i == 6)) {
        sel6[0] = best_i;
      }
      if ((i == 7)) {
        sel7[0] = best_i;
      }
      weights[i] = best_v;
      scores[best_i] = -1000000000.0f;
      i = (i + 1);
    }
    float max_v = weights[0];
    float sum_e = 0.0f;
    i = 0;
    while ((i < 8)) {
      float e = exp((weights[i] - max_v));
      weights[i] = e;
      sum_e = (sum_e + e);
      i = (i + 1);
    }
    float inv_s = (1.0f / sum_e);
    i = 0;
    while ((i < 8)) {
      weights[i] = (weights[i] * inv_s);
      i = (i + 1);
    }
  }
}

