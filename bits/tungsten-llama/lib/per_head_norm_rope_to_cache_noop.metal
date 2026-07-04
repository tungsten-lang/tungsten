#include <metal_stdlib>
using namespace metal;
kernel void per_head_norm_rope_to_cache_noop(
  device float *k_now [[buffer(0)]], device float *w [[buffer(1)]],
  device float *cos_tab [[buffer(2)]], device float *sin_tab [[buffer(3)]],
  device float *cache [[buffer(4)]],
  constant int &head_dim [[buffer(5)]], constant int &head_dim_half [[buffer(6)]],
  constant int &pos [[buffer(7)]], constant int &row_size [[buffer(8)]],
  constant float &inv_d [[buffer(9)]], constant float &eps [[buffer(10)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) { if (__simd_lane == 0) cache[pos * row_size + __tg_id * head_dim] = 0.0f; }
