// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void weighted_add(
  device float *dst [[buffer(0)]],
  device float *src [[buffer(1)]],
  constant float &w [[buffer(2)]],
  constant int &n [[buffer(3)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int i = int(__tid);
  if ((i < n)) {
    dst[i] = (dst[i] + (w * src[i]));
  }
}

