#include <metal_stdlib>
using namespace metal;
kernel void rms_norm_noop(
  device float *x [[buffer(0)]], device float *w [[buffer(1)]],
  device float *y [[buffer(2)]], constant int &n [[buffer(3)]],
  constant float &inv_n [[buffer(4)]], constant float &eps [[buffer(5)]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) { if (__simd_lane == 0) y[0] = 0.0f; }
