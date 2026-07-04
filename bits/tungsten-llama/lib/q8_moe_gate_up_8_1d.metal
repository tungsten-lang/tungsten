#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(128)]]
kernel void q8_moe_gate_up_8_1d(
  device const int *w_q_gate [[buffer(0)]],
  device const half *w_s_gate [[buffer(1)]],
  device const int *w_q_up [[buffer(2)]],
  device const half *w_s_up [[buffer(3)]],
  device const float *x [[buffer(4)]],
  device float *y_gate [[buffer(5)]],
  device float *y_up [[buffer(6)]],
  device const int *exp_ids [[buffer(7)]],
  constant int &k_dim [[buffer(8)]],
  constant int &n_rows [[buffer(9)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int row_blocks = n_rows / 4;
  int slot = int(__tg_id) / row_blocks;
  int row_block = int(__tg_id) - slot * row_blocks;
  int m = row_block * 4 + int(__simd_id);
  if (slot >= 8 || m >= n_rows) return;

  int expert_idx = exp_ids[slot];
  int lane = int(__simd_lane);
  int nb = k_dim / 32;
  int ints_per_row = k_dim / 4;
  int scales_per_expert = n_rows * nb;
  int ints_per_expert = n_rows * ints_per_row;
  int s_base = expert_idx * scales_per_expert;
  int q_base = expert_idx * ints_per_expert;

  float partial_g = 0.0f;
  float partial_u = 0.0f;
  int b = lane;
  while (b < nb) {
    half s_g = w_s_gate[s_base + m * nb + b];
    half s_u = w_s_up[s_base + m * nb + b];
    int row_off = q_base + m * ints_per_row + b * 8;
    int x_off = b * 32;

    device const int4 *qg_p = (device const int4*)(&w_q_gate[row_off]);
    device const int4 *qu_p = (device const int4*)(&w_q_up[row_off]);
    int4 qg_a = qg_p[0]; int4 qg_b = qg_p[1];
    int4 qu_a = qu_p[0]; int4 qu_b = qu_p[1];

    device const float4 *x_p = (device const float4*)(&x[x_off]);
    float4 x_0 = x_p[0]; float4 x_1 = x_p[1];
    float4 x_2 = x_p[2]; float4 x_3 = x_p[3];
    float4 x_4 = x_p[4]; float4 x_5 = x_p[5];
    float4 x_6 = x_p[6]; float4 x_7 = x_p[7];

    float bg = dot(float4(as_type<char4>(qg_a.x)), x_0);
    bg      += dot(float4(as_type<char4>(qg_a.y)), x_1);
    bg      += dot(float4(as_type<char4>(qg_a.z)), x_2);
    bg      += dot(float4(as_type<char4>(qg_a.w)), x_3);
    bg      += dot(float4(as_type<char4>(qg_b.x)), x_4);
    bg      += dot(float4(as_type<char4>(qg_b.y)), x_5);
    bg      += dot(float4(as_type<char4>(qg_b.z)), x_6);
    bg      += dot(float4(as_type<char4>(qg_b.w)), x_7);

    float bu = dot(float4(as_type<char4>(qu_a.x)), x_0);
    bu      += dot(float4(as_type<char4>(qu_a.y)), x_1);
    bu      += dot(float4(as_type<char4>(qu_a.z)), x_2);
    bu      += dot(float4(as_type<char4>(qu_a.w)), x_3);
    bu      += dot(float4(as_type<char4>(qu_b.x)), x_4);
    bu      += dot(float4(as_type<char4>(qu_b.y)), x_5);
    bu      += dot(float4(as_type<char4>(qu_b.z)), x_6);
    bu      += dot(float4(as_type<char4>(qu_b.w)), x_7);

    partial_g += float(s_g) * bg;
    partial_u += float(s_u) * bu;
    b += 32;
  }

  float total_g = simd_sum(partial_g);
  float total_u = simd_sum(partial_u);
  if (lane == 0) {
    y_gate[slot * n_rows + m] = total_g;
    y_up[slot * n_rows + m] = total_u;
  }
}
