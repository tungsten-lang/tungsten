// DEBUG ONLY — bypasses the matvec, writes 0. Used to isolate how much
// of the per-token wallclock the down expert matvec contributes.
#include <metal_stdlib>
using namespace metal;

kernel void q8_matvec_expert_noop(
  device int *w_q [[buffer(0)]],
  device half *w_s [[buffer(1)]],
  device float *x [[buffer(2)]],
  device float *y [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  constant int &n_rows [[buffer(5)]],
  constant int &expert_idx [[buffer(6)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  if (__simd_lane == 0) {
    y[__tg_id] = 0.0f;
  }
}
