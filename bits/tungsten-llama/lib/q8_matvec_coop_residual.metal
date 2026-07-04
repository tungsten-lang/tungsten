// Q8_0 matvec that accumulates into the output buffer (residual add)
// instead of overwriting it. Replaces the (q8_matvec → residual_add)
// pair, eliminating one barrier and one dispatch per layer.
//
// Use case: o_proj's matvec output is added to x_buf (the residual
// stream). Standard pattern: y = x + matvec(attn_out). Here y == x
// in-place, with the matvec result added to whatever x already holds.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void q8_matvec_coop_residual(
  device const int *w_q [[buffer(0)]],
  device const half *w_s [[buffer(1)]],
  device const float *x [[buffer(2)]],     // matvec input (e.g. attn_out)
  device float *y [[buffer(3)]],     // residual stream — read AND written
  constant int &k_dim [[buffer(4)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  int nb = k_dim / 32;
  int ints_per_row = k_dim / 4;

  float partial = 0.0f;
  int b = lane;
  while (b < nb) {
    half s = w_s[m * nb + b];
    int row_off = m * ints_per_row + b * 8;
    int x_off = b * 32;

    device int4 *q_p = (device int4*)(&w_q[row_off]);
    int4 q4_a = q_p[0];
    int4 q4_b = q_p[1];

    device float4 *x_p = (device float4*)(&x[x_off]);
    float4 x_0 = x_p[0];
    float4 x_1 = x_p[1];
    float4 x_2 = x_p[2];
    float4 x_3 = x_p[3];
    float4 x_4 = x_p[4];
    float4 x_5 = x_p[5];
    float4 x_6 = x_p[6];
    float4 x_7 = x_p[7];

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
    y[m] = y[m] + total;
  }
}
