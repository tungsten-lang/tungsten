// Write V from v_now (batched matvec output) into v_cache at pos_start..pos_start+BATCH-1.
// v_now is [BATCH × KV_ROW] f32; v_cache is [MAX_POS × KV_ROW] f32.
// Dispatch BATCH * KV_ROW threads.

#include <metal_stdlib>
using namespace metal;

constant int BATCH_FC  [[function_constant(0)]];
constant int KV_ROW_FC [[function_constant(1)]];

kernel void v_write_decode_batch_fc(
  device const float *v_now    [[buffer(0)]],
  device float       *v_cache  [[buffer(1)]],
  constant int &pos_start [[buffer(2)]],
  uint tid [[thread_position_in_grid]]
) {
  int total = BATCH_FC * KV_ROW_FC;
  if (int(tid) >= total) return;
  int token = int(tid) / KV_ROW_FC;
  int j = int(tid) - token * KV_ROW_FC;
  v_cache[(pos_start + token) * KV_ROW_FC + j] = v_now[token * KV_ROW_FC + j];
}
