// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void f16_matvec_to_cache(
  device half *w [[buffer(0)]],
  device float *x [[buffer(1)]],
  device float *cache [[buffer(2)]],
  constant int &k_dim [[buffer(3)]],
  constant int &pos [[buffer(4)]],
  constant int &row_size [[buffer(5)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  float partial = 0.0f;
  int i = lane;
  while ((i < k_dim)) {
    partial = (partial + (w[((m * k_dim) + i)] * x[i]));
    i = (i + 32);
  }
  float total = simd_sum(partial);
  if ((lane == 0)) {
    cache[((pos * row_size) + m)] = total;
  }
}

