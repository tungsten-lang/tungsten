// Argmax for each row of a [BATCH × N] logits matrix. 1 TG per batch row, 32 lanes.

#include <metal_stdlib>
using namespace metal;

constant int N_FC     [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

[[max_total_threads_per_threadgroup(32)]]
kernel void argmax_batch_fc(
  device const float *logits [[buffer(0)]],
  device int         *out    [[buffer(1)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg);
  if (token >= BATCH_FC) return;

  int base = token * N_FC;
  float max_v = -1.0e30f;
  int max_i = 0;
  for (int i = int(lane); i < N_FC; i += 32) {
    float v = logits[base + i];
    if (v > max_v) { max_v = v; max_i = i; }
  }
  // Reduce across simdgroup via repeated simd_shuffle_xor compare-and-swap.
  for (uint offset = 16; offset > 0; offset >>= 1) {
    float other_v = simd_shuffle_xor(max_v, offset);
    int other_i = simd_shuffle_xor(max_i, offset);
    if (other_v > max_v) { max_v = other_v; max_i = other_i; }
  }
  if (lane == 0) out[token] = max_i;
}
