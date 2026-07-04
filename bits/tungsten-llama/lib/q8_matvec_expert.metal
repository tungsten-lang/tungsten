// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void q8_matvec_expert(
  device int *w_q [[buffer(0)]],
  device half *w_s [[buffer(1)]],
  device float *x [[buffer(2)]],
  device float *y [[buffer(3)]],
  constant int &k_dim [[buffer(4)]],
  constant int &n_rows [[buffer(5)]],
  constant int &expert_idx [[buffer(6)]],
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
  float partial = 0.0f;
  int b = lane;
  while ((b < nb)) {
    half s = w_s[((s_base + (m * nb)) + b)];
    float block_acc = 0.0f;
    int row_off = ((q_base + (m * ints_per_row)) + (b * 8));
    int x_off = (b * 32);
    int i = 0;
    while ((i < 8)) {
      int packed = w_q[(row_off + i)];
      block_acc = ((((block_acc + (((packed << 24) >> 24) * x[(x_off + (i * 4))])) + (((packed << 16) >> 24) * x[((x_off + (i * 4)) + 1)])) + (((packed << 8) >> 24) * x[((x_off + (i * 4)) + 2)])) + ((packed >> 24) * x[((x_off + (i * 4)) + 3)]));
      i = (i + 1);
    }
    partial = (partial + (s * block_acc));
    b = (b + 32);
  }
  float total = simd_sum(partial);
  if ((lane == 0)) {
    y[m] = total;
  }
}

