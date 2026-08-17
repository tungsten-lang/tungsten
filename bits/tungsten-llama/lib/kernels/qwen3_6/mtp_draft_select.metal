// Draft-only argmax over Qwen3.8's compact vocabulary.
//
// The target model still scores the full vocabulary.  The MTP head only
// proposes tokens, so it can restrict its projection to the common-token
// prefix plus Qwen's text/control-token range without changing target parity.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void mtp_compact_draft_select(
  device const float *prefix_logits  [[buffer(0)]],
  device const float *control_logits [[buffer(1)]],
  device int         *result         [[buffer(2)]],
  constant int &prefix_count         [[buffer(3)]],
  constant int &control_count        [[buffer(4)]],
  constant int &control_start        [[buffer(5)]],
  uint lane [[thread_index_in_simdgroup]]) {
  float local_max = -INFINITY;

  for (int i = int(lane); i < prefix_count; i += 32) {
    local_max = max(local_max, prefix_logits[i]);
  }
  for (int i = int(lane); i < control_count; i += 32) {
    local_max = max(local_max, control_logits[i]);
  }

  const float global_max = simd_max(local_max);
  int local_id = INT_MAX;
  for (int i = int(lane); i < prefix_count; i += 32) {
    if (prefix_logits[i] == global_max) local_id = min(local_id, i);
  }
  for (int i = int(lane); i < control_count; i += 32) {
    if (control_logits[i] == global_max) {
      local_id = min(local_id, control_start + i);
    }
  }

  const int global_id = simd_min(local_id);
  if (lane == 0) result[0] = global_id;
}
