// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void moe_combine_8_residual(
  device float *x [[buffer(0)]],
  device float *eo0 [[buffer(1)]],
  device float *eo1 [[buffer(2)]],
  device float *eo2 [[buffer(3)]],
  device float *eo3 [[buffer(4)]],
  device float *eo4 [[buffer(5)]],
  device float *eo5 [[buffer(6)]],
  device float *eo6 [[buffer(7)]],
  device float *eo7 [[buffer(8)]],
  device float *weights [[buffer(9)]],
  constant int &n_rows [[buffer(10)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int i = int(__tid);
  if ((i < n_rows)) {
    float accum = x[i];
    accum = (accum + (weights[0] * eo0[i]));
    accum = (accum + (weights[1] * eo1[i]));
    accum = (accum + (weights[2] * eo2[i]));
    accum = (accum + (weights[3] * eo3[i]));
    accum = (accum + (weights[4] * eo4[i]));
    accum = (accum + (weights[5] * eo5[i]));
    accum = (accum + (weights[6] * eo6[i]));
    accum = (accum + (weights[7] * eo7[i]));
    x[i] = accum;
  }
}

