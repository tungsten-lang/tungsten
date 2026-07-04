// DEBUG ONLY — no-op variant of gate+up expert matvec.
#include <metal_stdlib>
using namespace metal;

kernel void q8_matvec_gate_up_expert_noop(
  device int *w_q_gate [[buffer(0)]],
  device half *w_s_gate [[buffer(1)]],
  device int *w_q_up [[buffer(2)]],
  device half *w_s_up [[buffer(3)]],
  device float *x [[buffer(4)]],
  device float *y_gate [[buffer(5)]],
  device float *y_up [[buffer(6)]],
  constant int &k_dim [[buffer(7)]],
  constant int &n_rows [[buffer(8)]],
  constant int &expert_idx [[buffer(9)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  if (__simd_lane == 0) {
    y_gate[__tg_id] = 0.0f;
    y_up[__tg_id] = 0.0f;
  }
}
