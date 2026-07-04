// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void q8_matvec_gate_up_expert(
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
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  int nb = (k_dim / 32);
  int ints_per_row = (k_dim / 4);
  int scales_per_expert = (n_rows * nb);
  int ints_per_expert = (n_rows * ints_per_row);
  int s_base = (expert_idx * scales_per_expert);
  int q_base = (expert_idx * ints_per_expert);
  float partial_g = 0.0f;
  float partial_u = 0.0f;
  int b = lane;
  while ((b < nb)) {
    half s_g = w_s_gate[((s_base + (m * nb)) + b)];
    half s_u = w_s_up[((s_base + (m * nb)) + b)];
    float block_g = 0.0f;
    float block_u = 0.0f;
    int row_off = ((q_base + (m * ints_per_row)) + (b * 8));
    int x_off = (b * 32);
    int i = 0;
    while ((i < 8)) {
      int pg = w_q_gate[(row_off + i)];
      int pu = w_q_up[(row_off + i)];
      float x0 = x[(x_off + (i * 4))];
      float x1 = x[((x_off + (i * 4)) + 1)];
      float x2 = x[((x_off + (i * 4)) + 2)];
      float x3 = x[((x_off + (i * 4)) + 3)];
      block_g = ((((block_g + (((pg << 24) >> 24) * x0)) + (((pg << 16) >> 24) * x1)) + (((pg << 8) >> 24) * x2)) + ((pg >> 24) * x3));
      block_u = ((((block_u + (((pu << 24) >> 24) * x0)) + (((pu << 16) >> 24) * x1)) + (((pu << 8) >> 24) * x2)) + ((pu >> 24) * x3));
      i = (i + 1);
    }
    partial_g = (partial_g + (s_g * block_g));
    partial_u = (partial_u + (s_u * block_u));
    b = (b + 32);
  }
  float total_g = simd_sum(partial_g);
  float total_u = simd_sum(partial_u);
  if ((lane == 0)) {
    y_gate[m] = total_g;
    y_up[m] = total_u;
  }
}

