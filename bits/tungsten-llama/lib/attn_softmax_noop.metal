#include <metal_stdlib>
using namespace metal;
kernel void attn_softmax_noop(
  device float *x [[buffer(0)]], constant int &n [[buffer(1)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) { if (__simd_lane == 0) x[__tg_id * n] = 0.0f; }
