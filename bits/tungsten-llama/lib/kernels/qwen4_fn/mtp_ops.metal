// MTP head ops for Qwen3.8-Flash-Next: hidden+embedding fusion and the
// bf16 fused-expert MoE gather (the MTP layer's experts stay bf16 —
// gate_up_proj [512, 1280, 2560] fused gate|up, down_proj [512, 2560, 640]).

#include <metal_stdlib>
using namespace metal;

static inline float mtp_bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

// h_m[t, s*d + i] = h_fc[t, s*d + i] + e_fc[t, i]  (embedding broadcast
// across the S hyper-connection branches). Dispatch: n*S*d threads.
kernel void mtp_fuse_add(
  device const float *__restrict__ h_fc [[buffer(0)]],   // [n, S*d]
  device const float *__restrict__ e_fc [[buffer(1)]],   // [n, d]
  device       float *__restrict__ out  [[buffer(2)]],   // [n, S*d]
  constant int &S [[buffer(3)]],
  constant int &d [[buffer(4)]],
  constant int &n [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * S * d) return;
  int t = gi / (S * d);
  int i = gi % d;
  out[gi] = h_fc[gi] + e_fc[t * d + i];
}

// Token-major bf16 expert gather matvec, mirroring moe_gather_matvec_multi's
// structure (8 rows per TG: 2 simdgroups x 4 rows) with bf16 loads and the
// bf16_matvec summation (lane-strided k, simd_sum).
// Dispatch: n * K * (n_rows/8) TGs of 64.
[[max_total_threads_per_threadgroup(64)]]
kernel void bf16_moe_gather_multi(
  device const ushort *__restrict__ w        [[buffer(0)]],   // [512, rows_total, k_dim]
  device const int    *__restrict__ indices  [[buffer(1)]],   // [n, K]
  device const float  *__restrict__ x        [[buffer(2)]],
  device       float  *__restrict__ y        [[buffer(3)]],   // [n, K, n_rows]
  constant int &k_dim         [[buffer(4)]],
  constant int &n_rows        [[buffer(5)]],
  constant int &expert_stride [[buffer(6)]],   // elements per expert
  constant int &row_off       [[buffer(7)]],   // first row inside the expert block
  constant int &K             [[buffer(8)]],
  constant int &x_is_per_expert [[buffer(9)]], // 0: x[t,:]; 1: x[t,k,:]
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int tgs_per_k = n_rows / 8;
  int tg = int(__tg_id);
  int tk = tg / tgs_per_k;
  int m_block = tg % tgs_per_k;
  int expert = indices[tk];
  int t = tk / K;
  int m_start = m_block * 8 + int(__simd_id) * 4;
  int lane = int(__simd_lane);
  device const ushort *w_base = w + (ulong)(uint)expert * (ulong)(uint)expert_stride;
  int x_base = x_is_per_expert != 0 ? tk * k_dim : t * k_dim;
  for (int r = 0; r < 4; r++) {
    int row = m_start + r;
    device const ushort *w_row = w_base + (ulong)(uint)(row_off + row) * (ulong)(uint)k_dim;
    float partial = 0.0f;
    for (int i = lane; i < k_dim; i += 32) {
      partial += mtp_bf16_to_f32(w_row[i]) * x[x_base + i];
    }
    float total = simd_sum(partial);
    if (lane == 0) y[tk * n_rows + row] = total;
  }
}

// Split the fused gate|up gather output and apply silu-mul:
// eh[t,k,j] = silu(egu[t,k,j]) * egu[t,k,ffn+j]. Dispatch: n*K*ffn threads.
kernel void mtp_gu_silu(
  device const float *__restrict__ egu [[buffer(0)]],   // [n, K, 2*ffn]
  device       float *__restrict__ eh  [[buffer(1)]],   // [n, K, ffn]
  constant int &ffn [[buffer(2)]],
  constant int &total [[buffer(3)]],                    // n*K*ffn
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= total) return;
  int tk = gi / ffn;
  int j = gi % ffn;
  float g = egu[tk * 2 * ffn + j];
  float u = egu[tk * 2 * ffn + ffn + j];
  float s = g / (1.0f + exp(-g));
  eh[gi] = s * u;
}
