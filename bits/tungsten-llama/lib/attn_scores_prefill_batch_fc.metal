#include <metal_stdlib>
using namespace metal;

constant int HEAD_DIM_FC [[function_constant(0)]];
constant int N_Q_HEADS_FC [[function_constant(1)]];
constant int N_KV_HEADS_FC [[function_constant(2)]];
constant int GROUP_SIZE_FC [[function_constant(3)]];
constant int BATCH_FC [[function_constant(4)]];

kernel void attn_scores_prefill_batch_fc(
  device const float *q [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device float *scores [[buffer(2)]],
  constant float &scale [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int t = int(tid) % BATCH_FC;
  int tmp = int(tid) / BATCH_FC;
  int h = tmp % N_Q_HEADS_FC;
  int token = tmp / N_Q_HEADS_FC;
  if (token >= BATCH_FC) return;

  int out_base = (token * N_Q_HEADS_FC + h) * BATCH_FC;
  if (t > token) {
    scores[out_base + t] = -1.0e30f;
    return;
  }

  int kv_h = h / GROUP_SIZE_FC;
  int q_off = token * N_Q_HEADS_FC * HEAD_DIM_FC + h * HEAD_DIM_FC;
  int k_off = (t * N_KV_HEADS_FC + kv_h) * HEAD_DIM_FC;
  float dot = 0.0f;
  for (int j = 0; j < HEAD_DIM_FC; j++) {
    dot += q[q_off + j] * k_cache[k_off + j];
  }
  scores[out_base + t] = dot * scale;
}
