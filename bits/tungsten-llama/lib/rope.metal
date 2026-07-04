// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void rope_neox(
  device float *x [[buffer(0)]],
  device float *cos_tab [[buffer(1)]],
  device float *sin_tab [[buffer(2)]],
  constant int &head_dim [[buffer(3)]],
  constant int &head_dim_half [[buffer(4)]],
  constant int &n_heads [[buffer(5)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int tid = int(__tid);
  int head = (tid / head_dim_half);
  int pair = (tid % head_dim_half);
  int base_off = (head * head_dim);
  int i_lo = (base_off + pair);
  int i_hi = (i_lo + head_dim_half);
  float a = x[i_lo];
  float b = x[i_hi];
  float c = cos_tab[pair];
  float s = sin_tab[pair];
  x[i_lo] = ((a * c) - (b * s));
  x[i_hi] = ((a * s) + (b * c));
}

