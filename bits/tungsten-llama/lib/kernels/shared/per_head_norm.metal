// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void per_head_norm(
  device float *x [[buffer(0)]],
  device float *w [[buffer(1)]],
  constant int &head_dim [[buffer(2)]],
  constant float &inv_d [[buffer(3)]],
  constant float &eps [[buffer(4)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int h = int(__tg_id);
  int lane = int(__simd_lane);
  int base = (h * head_dim);
  float sum_sq = 0.0f;
  int i = lane;
  while ((i < head_dim)) {
    float v = x[(base + i)];
    sum_sq = (sum_sq + (v * v));
    i = (i + 32);
  }
  float total = simd_sum(sum_sq);
  float rrms = (1.0f / sqrt(((total * inv_d) + eps)));
  i = lane;
  while ((i < head_dim)) {
    x[(base + i)] = ((x[(base + i)] * rrms) * w[i]);
    i = (i + 32);
  }
}

