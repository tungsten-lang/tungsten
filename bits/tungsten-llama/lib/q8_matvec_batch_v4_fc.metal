#include <metal_stdlib>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

[[max_total_threads_per_threadgroup(1024)]]
kernel void q8_matvec_batch_v4_fc(
  device const int *w_q [[buffer(0)]],
  device const half *w_s [[buffer(1)]],
  device const float *x [[buffer(2)]],
  device float *y [[buffer(3)]],
  threadgroup float *tg_x [[threadgroup(0)]],
  uint tid [[thread_position_in_threadgroup]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd_id [[simdgroup_index_in_threadgroup]]
) {
  const int row_blocks = N_ROWS_FC / 32;
  int token = int(tg) / row_blocks;
  int row_block = int(tg) - token * row_blocks;
  if (token >= BATCH_FC) return;

  int x_base = token * K_DIM_FC;
  for (int i = int(tid); i < K_DIM_FC; i += 1024) {
    tg_x[i] = x[x_base + i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  int m = row_block * 32 + int(simd_id);
  if (m >= N_ROWS_FC) return;

  const int nb = K_DIM_FC / 32;
  const int ints_per_row = K_DIM_FC / 4;
  float partial = 0.0f;
  for (int b = int(lane); b < nb; b += 32) {
    half s = w_s[m * nb + b];
    int row_off = m * ints_per_row + b * 8;
    int x_off = b * 32;

    device const int4 *q_p = (device const int4*)(&w_q[row_off]);
    int4 q4_a = q_p[0]; int4 q4_b = q_p[1];
    threadgroup float4 *x_p = (threadgroup float4*)(&tg_x[x_off]);
    float4 x_0 = x_p[0]; float4 x_1 = x_p[1];
    float4 x_2 = x_p[2]; float4 x_3 = x_p[3];
    float4 x_4 = x_p[4]; float4 x_5 = x_p[5];
    float4 x_6 = x_p[6]; float4 x_7 = x_p[7];

    float block_acc = dot(float4(as_type<char4>(q4_a.x)), x_0);
    block_acc += dot(float4(as_type<char4>(q4_a.y)), x_1);
    block_acc += dot(float4(as_type<char4>(q4_a.z)), x_2);
    block_acc += dot(float4(as_type<char4>(q4_a.w)), x_3);
    block_acc += dot(float4(as_type<char4>(q4_b.x)), x_4);
    block_acc += dot(float4(as_type<char4>(q4_b.y)), x_5);
    block_acc += dot(float4(as_type<char4>(q4_b.z)), x_6);
    block_acc += dot(float4(as_type<char4>(q4_b.w)), x_7);
    partial += float(s) * block_acc;
  }

  float total = simd_sum(partial);
  if (lane == 0) y[token * N_ROWS_FC + m] = total;
}
