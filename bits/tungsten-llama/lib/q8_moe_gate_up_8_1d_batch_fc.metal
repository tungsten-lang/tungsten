#include <metal_stdlib>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

[[max_total_threads_per_threadgroup(128)]]
kernel void q8_moe_gate_up_8_1d_batch_fc(
  device const int *w_q_gate [[buffer(0)]],
  device const half *w_s_gate [[buffer(1)]],
  device const int *w_q_up [[buffer(2)]],
  device const half *w_s_up [[buffer(3)]],
  device const float *x [[buffer(4)]],
  device float *y_gate [[buffer(5)]],
  device float *y_up [[buffer(6)]],
  device const int *exp_ids [[buffer(7)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd_id [[simdgroup_index_in_threadgroup]]
) {
  const int row_blocks = N_ROWS_FC / 4;
  const int groups_per_token = 8 * row_blocks;
  int token = int(tg) / groups_per_token;
  int rem = int(tg) - token * groups_per_token;
  int slot = rem / row_blocks;
  int row_block = rem - slot * row_blocks;
  int m = row_block * 4 + int(simd_id);
  if (token >= BATCH_FC || slot >= 8 || m >= N_ROWS_FC) return;

  int expert_idx = exp_ids[token * 8 + slot];
  const int nb = K_DIM_FC / 32;
  const int ints_per_row = K_DIM_FC / 4;
  const int scales_per_expert = N_ROWS_FC * nb;
  const int ints_per_expert = N_ROWS_FC * ints_per_row;
  int s_base = expert_idx * scales_per_expert;
  int q_base = expert_idx * ints_per_expert;
  int x_base = token * K_DIM_FC;

  float partial_g = 0.0f;
  float partial_u = 0.0f;
  for (int b = int(lane); b < nb; b += 32) {
    half s_g = w_s_gate[s_base + m * nb + b];
    half s_u = w_s_up[s_base + m * nb + b];
    int row_off = q_base + m * ints_per_row + b * 8;
    int x_off = x_base + b * 32;

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
    bg += dot(float4(as_type<char4>(qg_a.y)), x_1);
    bg += dot(float4(as_type<char4>(qg_a.z)), x_2);
    bg += dot(float4(as_type<char4>(qg_a.w)), x_3);
    bg += dot(float4(as_type<char4>(qg_b.x)), x_4);
    bg += dot(float4(as_type<char4>(qg_b.y)), x_5);
    bg += dot(float4(as_type<char4>(qg_b.z)), x_6);
    bg += dot(float4(as_type<char4>(qg_b.w)), x_7);

    float bu = dot(float4(as_type<char4>(qu_a.x)), x_0);
    bu += dot(float4(as_type<char4>(qu_a.y)), x_1);
    bu += dot(float4(as_type<char4>(qu_a.z)), x_2);
    bu += dot(float4(as_type<char4>(qu_a.w)), x_3);
    bu += dot(float4(as_type<char4>(qu_b.x)), x_4);
    bu += dot(float4(as_type<char4>(qu_b.y)), x_5);
    bu += dot(float4(as_type<char4>(qu_b.z)), x_6);
    bu += dot(float4(as_type<char4>(qu_b.w)), x_7);

    partial_g += float(s_g) * bg;
    partial_u += float(s_u) * bu;
  }

  float total_g = simd_sum(partial_g);
  float total_u = simd_sum(partial_u);
  if (lane == 0) {
    int out = (token * 8 + slot) * N_ROWS_FC + m;
    y_gate[out] = total_g;
    y_up[out] = total_u;
  }
}
