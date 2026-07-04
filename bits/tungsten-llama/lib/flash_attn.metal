// Fused attention: scores → softmax → weighted_sum, all in one
// dispatch with threadgroup memory holding the per-head scores.
// Replaces (attn_scores → barrier → attn_softmax → barrier → wsum)
// = 3 dispatches + 2 barriers per layer with 1 dispatch + 0 internal
// barriers visible to the encoder. Saves 96 barriers per token.
//
// Decomposition: 1 threadgroup per Q head, 32 lanes (one simdgroup).
// tg_scores[MAX_POS] is shared across the simdgroup via threadgroup
// memory.
//
// Phase 1: each lane computes s_t for t in stride (lane, lane+32, ...)
//          via Q·K[t]*scale. Writes to tg_scores[t].
// Phase 2: cooperative softmax over the row via simd_max + simd_sum.
//          tg_scores[] becomes normalized weights.
// Phase 3: each lane computes head_dim/32 output positions. For each,
//          sums over t of tg_scores[t] * V[t][j].

#include <metal_stdlib>
using namespace metal;

kernel void flash_attn(
  device float *q        [[buffer(0)]],   // [n_q_heads * head_dim]
  device float *k_cache  [[buffer(1)]],   // [max_pos, n_kv_heads * head_dim]
  device float *v_cache  [[buffer(2)]],
  device float *out      [[buffer(3)]],   // [n_q_heads * head_dim]
  constant int   &head_dim    [[buffer(4)]],
  constant int   &n_kv_heads  [[buffer(5)]],
  constant int   &group_size  [[buffer(6)]],
  constant int   &n_pos       [[buffer(7)]],
  constant float &scale       [[buffer(8)]],
  threadgroup float *tg_scores [[threadgroup(0)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int h = int(__tg_id);
  int lane = int(__simd_lane);
  int kv_h = h / group_size;
  int q_off = h * head_dim;
  int row_size = n_kv_heads * head_dim;

  // Phase 1: compute scores. Each lane handles stride of t positions.
  for (int t = lane; t < n_pos; t += 32) {
    int k_off = t * row_size + kv_h * head_dim;
    float dot = 0.0f;
    for (int j = 0; j < head_dim; j++) {
      dot += q[q_off + j] * k_cache[k_off + j];
    }
    tg_scores[t] = dot * scale;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Phase 2: softmax. Cooperative max + sum across the simdgroup.
  float m_local = -1e30f;
  for (int t = lane; t < n_pos; t += 32) {
    if (tg_scores[t] > m_local) m_local = tg_scores[t];
  }
  float m = simd_max(m_local);

  float s_local = 0.0f;
  for (int t = lane; t < n_pos; t += 32) {
    float e = exp(tg_scores[t] - m);
    tg_scores[t] = e;
    s_local += e;
  }
  float s = simd_sum(s_local);
  float inv_s = 1.0f / s;

  for (int t = lane; t < n_pos; t += 32) {
    tg_scores[t] *= inv_s;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Phase 3: weighted sum over values. Each lane handles head_dim/32
  // output positions (for head_dim=128 → 4 per lane).
  for (int k_idx = 0; k_idx < (head_dim + 31) / 32; k_idx++) {
    int j = lane + k_idx * 32;
    if (j < head_dim) {
      float acc = 0.0f;
      for (int t = 0; t < n_pos; t++) {
        acc += tg_scores[t] * v_cache[t * row_size + kv_h * head_dim + j];
      }
      out[h * head_dim + j] = acc;
    }
  }
}
