// Weighted sum over V cache for decode-batch attention.
// Out[token, h, j] = sum_{t in 0..pos_start+token} scores[token, h, t] * v_cache[t, kv_h, j].

#include <metal_stdlib>
using namespace metal;

constant int HEAD_DIM_FC   [[function_constant(0)]];
constant int N_Q_HEADS_FC  [[function_constant(1)]];
constant int N_KV_HEADS_FC [[function_constant(2)]];
constant int GROUP_SIZE_FC [[function_constant(3)]];
constant int BATCH_FC      [[function_constant(4)]];
constant int MAX_POS_FC    [[function_constant(5)]];

kernel void attn_weighted_sum_decode_batch_fc(
  device const float *scores  [[buffer(0)]],
  device const float *v_cache [[buffer(1)]],
  device float       *out     [[buffer(2)]],
  constant int &pos_start     [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int total = BATCH_FC * N_Q_HEADS_FC * HEAD_DIM_FC;
  if (int(tid) >= total) return;

  int j = int(tid) % HEAD_DIM_FC;
  int tmp = int(tid) / HEAD_DIM_FC;
  int h = tmp % N_Q_HEADS_FC;
  int token = tmp / N_Q_HEADS_FC;

  int kv_h = h / GROUP_SIZE_FC;
  int my_max_pos = pos_start + token + 1;
  int scores_off = (token * N_Q_HEADS_FC + h) * MAX_POS_FC;
  float accum = 0.0f;
  for (int t = 0; t < my_max_pos; t++) {
    int v_off = (t * N_KV_HEADS_FC + kv_h) * HEAD_DIM_FC + j;
    accum += scores[scores_off + t] * v_cache[v_off];
  }
  out[token * N_Q_HEADS_FC * HEAD_DIM_FC + h * HEAD_DIM_FC + j] = accum;
}
