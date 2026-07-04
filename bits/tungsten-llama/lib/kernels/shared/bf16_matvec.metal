// BF16 weight matvec: y[m] = dot(w[m, :], x[:]) for m in [0, n_rows).
// ollama's MLX qwen3.6 export keeps a handful of tensors in BF16 rather than
// nvfp4 — the MoE router (mlp.gate [256, hidden]), the shared-expert gate
// ([1, hidden]) and lm_head ([vocab, hidden]). This is the bf16 twin of
// shared/f32_matvec.metal: one threadgroup (one simdgroup) per output row.
//
// bf16->f32 is the top-16-bits-of-f32 layout: float = (bits << 16).
//
// Dispatch: metal_dispatch_groups(queue, pipe, [w, x, y, k_dim], n_rows, 32)
// (n_rows threadgroups of 32 threads each).

#include <metal_stdlib>
using namespace metal;

static inline float bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

kernel void bf16_matvec(
  device const ushort *__restrict__ w [[buffer(0)]],   // [n_rows, k_dim] bf16
  device const float  *__restrict__ x [[buffer(1)]],   // [k_dim] f32
  device float        *__restrict__ y [[buffer(2)]],   // [n_rows] f32
  constant int &k_dim [[buffer(3)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);
  float partial = 0.0f;
  int i = lane;
  while (i < k_dim) {
    partial += bf16_to_f32(w[m * k_dim + i]) * x[i];
    i += 32;
  }
  float total = simd_sum(partial);
  if (lane == 0) {
    y[m] = total;
  }
}
