// Q8_0 expert matvec with 4 output rows per threadgroup. Each TG has
// 4 simdgroups (128 threads); each simdgroup independently computes
// one output row. Dispatch (n_rows/4) threadgroups instead of n_rows.
//
// Goal: better Apple GPU occupancy. With 128 threads/TG, each shader
// core can keep more work in flight to hide DRAM latency.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(128)]]
kernel void q8_matvec_expert_v3(
  device const int *__restrict__ w_q [[buffer(0)]],
  device const half *__restrict__ w_s [[buffer(1)]],
  device const float *__restrict__ x [[buffer(2)]],
  device float *__restrict__ y [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  constant int &n_rows [[buffer(5)]],
  constant int &expert_idx [[buffer(6)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int m = int(__tg_id) * 4 + int(__simd_id);
  if (m >= n_rows) return;
  int lane = int(__simd_lane);
  int nb = k_dim / 32;
  int ints_per_row = k_dim / 4;
  int scales_per_expert = n_rows * nb;
  int ints_per_expert = n_rows * ints_per_row;
  int s_base = expert_idx * scales_per_expert;
  int q_base_ints = expert_idx * ints_per_expert;

  float partial = 0.0f;
  int b = lane;
  while (b < nb) {
    half s = w_s[s_base + m * nb + b];
    int row_off_ints = q_base_ints + m * ints_per_row + b * 8;
    int x_off = b * 32;

    device int4 *q_p = (device int4*)(&w_q[row_off_ints]);
    int4 q4_a = q_p[0];
    int4 q4_b = q_p[1];

    device float4 *x_p = (device float4*)(&x[x_off]);
    float4 x_0 = x_p[0]; float4 x_1 = x_p[1];
    float4 x_2 = x_p[2]; float4 x_3 = x_p[3];
    float4 x_4 = x_p[4]; float4 x_5 = x_p[5];
    float4 x_6 = x_p[6]; float4 x_7 = x_p[7];

    float block_acc = dot(float4(as_type<char4>(q4_a.x)), x_0);
    block_acc      += dot(float4(as_type<char4>(q4_a.y)), x_1);
    block_acc      += dot(float4(as_type<char4>(q4_a.z)), x_2);
    block_acc      += dot(float4(as_type<char4>(q4_a.w)), x_3);
    block_acc      += dot(float4(as_type<char4>(q4_b.x)), x_4);
    block_acc      += dot(float4(as_type<char4>(q4_b.y)), x_5);
    block_acc      += dot(float4(as_type<char4>(q4_b.z)), x_6);
    block_acc      += dot(float4(as_type<char4>(q4_b.w)), x_7);

    partial += float(s) * block_acc;
    b += 32;
  }

  float total = simd_sum(partial);
  if (lane == 0) {
    y[m] = total;
  }
}
