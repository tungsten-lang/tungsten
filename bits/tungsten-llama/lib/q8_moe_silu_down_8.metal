// 8-expert fused silu+down: ONE dispatch handles all 8 selected experts.
// Replaces the 8-dispatch loop. Each TG processes (slot, row_block).
// Grid: (n_rows/32) × 8. tg_id.x = row_block, tg_id.y = slot.
//
// Structure: 1024 threads per TG (32 simdgroups × 32 lanes). Phase 1
// stages h = silu(g) * u for this slot's expert into TG memory; phase 2
// computes 32 down output rows for this slot.

#include <metal_stdlib>
using namespace metal;

kernel void q8_moe_silu_down_8(
  device int *w_q [[buffer(0)]],         // shared down weights tensor [128 experts × n_rows × k_dim/4]
  device half *w_s [[buffer(1)]],
  device float *hg_packed [[buffer(2)]], // [TOP_K × EXPERT_FFN]
  device float *hu_packed [[buffer(3)]],
  device float *eo_packed [[buffer(4)]], // [TOP_K × HIDDEN]
  device int *exp_ids [[buffer(5)]],     // [TOP_K] expert IDs
  constant int &k_dim [[buffer(6)]],
  constant int &n_rows [[buffer(7)]],
  threadgroup float *tg_h [[threadgroup(0)]],
  uint2 __tg_id [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int slot = int(__tg_id.y);
  int row_block = int(__tg_id.x);
  int expert_idx = exp_ids[slot];

  int hg_off = slot * k_dim;
  int eo_off = slot * n_rows;
  int tid = int(__tid_in_tg);

  // Phase 1: compute h[i] = silu(hg[i]) * hu[i] into TG memory
  if (tid < k_dim) {
    float g = hg_packed[hg_off + tid];
    float u = hu_packed[hg_off + tid];
    float sg = g / (1.0f + exp(-g));
    tg_h[tid] = sg * u;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Phase 2: each simdgroup computes one output row of the down matvec
  int m = row_block * 32 + int(__simd_id);
  if (m >= n_rows) return;
  int lane = int(__simd_lane);
  int nb = k_dim / 32;
  int ints_per_row = k_dim / 4;
  int scales_per_expert = n_rows * nb;
  int ints_per_expert = n_rows * ints_per_row;
  int s_base = expert_idx * scales_per_expert;
  int q_base = expert_idx * ints_per_expert;

  float partial = 0.0f;
  int b = lane;
  while (b < nb) {
    half s = w_s[s_base + m * nb + b];
    int row_off = q_base + m * ints_per_row + b * 8;
    int x_off = b * 32;

    device int4 *q_p = (device int4*)(&w_q[row_off]);
    int4 q4_a = q_p[0]; int4 q4_b = q_p[1];

    threadgroup float4 *x_p = (threadgroup float4*)(&tg_h[x_off]);
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
    eo_packed[eo_off + m] = total;
  }
}
