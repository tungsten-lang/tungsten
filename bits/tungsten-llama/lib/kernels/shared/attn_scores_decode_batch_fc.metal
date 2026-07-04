// Attention scores for batched decode (K candidate tokens at positions
// pos_start..pos_start+BATCH-1, each attending to all positions [0, pos_start+t]).
//
// Dispatch BATCH × N_Q_HEADS × MAX_POS threads.
// scores layout: scores[token * N_Q_HEADS * MAX_POS + h * MAX_POS + kv_pos]

#include <metal_stdlib>
using namespace metal;

constant int HEAD_DIM_FC   [[function_constant(0)]];
constant int N_Q_HEADS_FC  [[function_constant(1)]];
constant int N_KV_HEADS_FC [[function_constant(2)]];
constant int GROUP_SIZE_FC [[function_constant(3)]];
constant int BATCH_FC      [[function_constant(4)]];
constant int MAX_POS_FC    [[function_constant(5)]];

kernel void attn_scores_decode_batch_fc(
  device const float *q       [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device float       *scores  [[buffer(2)]],
  constant int   &pos_start   [[buffer(3)]],
  constant float &scale       [[buffer(4)]],
  uint tid [[thread_position_in_grid]]
) {
  int total = BATCH_FC * N_Q_HEADS_FC * MAX_POS_FC;
  if (int(tid) >= total) return;

  int kv_pos = int(tid) % MAX_POS_FC;
  int tmp = int(tid) / MAX_POS_FC;
  int h = tmp % N_Q_HEADS_FC;
  int token = tmp / N_Q_HEADS_FC;

  int my_max_pos = pos_start + token + 1;
  int out_off = (token * N_Q_HEADS_FC + h) * MAX_POS_FC + kv_pos;
  if (kv_pos >= my_max_pos) {
    scores[out_off] = -1.0e30f;
    return;
  }

  int kv_h = h / GROUP_SIZE_FC;
  int q_off = (token * N_Q_HEADS_FC + h) * HEAD_DIM_FC;
  int k_off = (kv_pos * N_KV_HEADS_FC + kv_h) * HEAD_DIM_FC;
  float dot = 0.0f;
  for (int j = 0; j < HEAD_DIM_FC; j++) {
    dot += q[q_off + j] * k_cache[k_off + j];
  }
  scores[out_off] = dot * scale;
}
