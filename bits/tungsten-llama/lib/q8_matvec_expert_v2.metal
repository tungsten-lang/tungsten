// Hand-tuned Q8_0 expert matvec — vectorized loads + dot product.
//
// Differences vs Tungsten-emitted q8_matvec_expert:
//   - Read packed quants 16 bytes at a time (int4) instead of 4 bytes
//     (int). One int4 carries 16 i8 weights.
//   - Read x 16 bytes at a time (float4) instead of 4 bytes (float).
//   - Unpack each int → 4 i8 → float4 via reinterpret + conversion.
//   - Use dot() instead of 4 scalar mul+adds per int.
//
// Same dispatch shape: n_rows threadgroups × 32 lanes. Same input
// memory layout. Drop-in replacement.

#include <metal_stdlib>
using namespace metal;

kernel void q8_matvec_expert_v2(
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
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  int nb = k_dim / 32;                      // blocks per row (each 32 weights)
  int ints_per_row = k_dim / 4;             // i32 quants per row
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

    // Load 32 packed weights = 8 int32 = 2 int4
    device int4 *q_p = (device int4*)(&w_q[row_off_ints]);
    int4 q4_a = q_p[0];
    int4 q4_b = q_p[1];

    // Load 32 floats from x = 8 float4
    device float4 *x_p = (device float4*)(&x[x_off]);
    float4 x_0 = x_p[0];
    float4 x_1 = x_p[1];
    float4 x_2 = x_p[2];
    float4 x_3 = x_p[3];
    float4 x_4 = x_p[4];
    float4 x_5 = x_p[5];
    float4 x_6 = x_p[6];
    float4 x_7 = x_p[7];

    // Unpack each i32 → 4×i8 → float4, dot with paired x4. Sign-extend
    // happens in the float4(char4) conversion.
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
