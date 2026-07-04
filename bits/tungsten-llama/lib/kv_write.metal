// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void kv_write(
  device float *k_now [[buffer(0)]],
  device float *cache [[buffer(1)]],
  constant int &pos [[buffer(2)]],
  constant int &row_size [[buffer(3)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int i = int(__tid);
  if ((i < row_size)) {
    cache[((pos * row_size) + i)] = k_now[i];
  }
}

