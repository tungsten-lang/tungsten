#include <metal_stdlib>
using namespace metal;
kernel void per_head_norm_rope_noop(
  device float *x [[buffer(0)]], device float *w [[buffer(1)]],
  device float *cos_tab [[buffer(2)]], device float *sin_tab [[buffer(3)]],
  constant int &head_dim [[buffer(4)]], constant int &head_dim_half [[buffer(5)]],
  constant float &inv_d [[buffer(6)]], constant float &eps [[buffer(7)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) { if (__simd_lane == 0) x[__tg_id * head_dim] = 0.0f; }
