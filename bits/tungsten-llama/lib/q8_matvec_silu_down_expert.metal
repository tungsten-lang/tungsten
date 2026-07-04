// Fused (silu(gate) * up) → down matvec, single dispatch per expert.
// Replaces (silu_mul → barrier → down) with a single kernel that
// stages h = silu(g) * u in threadgroup memory then matvec'd into eo.
//
// TG = 1024 threads (32 simdgroups × 32 lanes).
// Phase 1: threads 0..k_dim-1 compute h[i] = silu(hg[i]) * hu[i] into
//          tg_h[i]. Threads ≥ k_dim sit idle for this phase.
// threadgroup_barrier
// Phase 2: each of the 32 simdgroups computes one output row of the
//          down matvec, reading h from tg_h. 32 rows per TG; dispatch
//          n_rows / 32 TGs.
//
// k_dim = EXPERT_FFN = 768 fits in 1024 threads ✓
// tg_h memory = 768 * 4 = 3 KB ✓

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(1024)]]
kernel void q8_matvec_silu_down_expert(
  device const int *__restrict__ w_q [[buffer(0)]],
  device const half *__restrict__ w_s [[buffer(1)]],
  device const float *__restrict__ hg [[buffer(2)]],
  device const float *__restrict__ hu [[buffer(3)]],
  device float *__restrict__ y [[buffer(4)]],
  constant int &k_dim [[buffer(5)]],
  constant int &n_rows [[buffer(6)]],
  constant int &expert_idx [[buffer(7)]],
  threadgroup float *tg_h [[threadgroup(0)]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int tid = int(__tid_in_tg);

  // Phase 1: compute h[i] = silu(hg[i]) * hu[i] for i in [0, k_dim)
  if (tid < k_dim) {
    float g = hg[tid];
    float u = hu[tid];
    float sg = g / (1.0f + exp(-g));
    tg_h[tid] = sg * u;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Phase 2: each simdgroup computes one output row of the matvec.
  int m = int(__tg_id) * 32 + int(__simd_id);
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
    y[m] = total;
  }
}
