// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void residual_add(
  device float *a [[buffer(0)]],
  device float *b [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int i = int(__tid);
  if ((i < n)) {
    a[i] = (a[i] + b[i]);
  }
}

