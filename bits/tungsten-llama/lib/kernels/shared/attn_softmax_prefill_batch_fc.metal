#include <metal_stdlib>
using namespace metal;

constant int N_Q_HEADS_FC [[function_constant(0)]];
constant int BATCH_FC [[function_constant(1)]];

[[max_total_threads_per_threadgroup(32)]]
kernel void attn_softmax_prefill_batch_fc(
  device float *x [[buffer(0)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg) / N_Q_HEADS_FC;
  int h = int(tg) - token * N_Q_HEADS_FC;
  if (token >= BATCH_FC) return;

  int n = token + 1;
  int base = (token * N_Q_HEADS_FC + h) * BATCH_FC;
  float m_local = -1.0e30f;
  for (int i = int(lane); i < n; i += 32) {
    m_local = max(m_local, x[base + i]);
  }
  float m = simd_max(m_local);
  float s_local = 0.0f;
  for (int i = int(lane); i < n; i += 32) {
    s_local += exp(x[base + i] - m);
  }
  float inv_s = 1.0f / simd_sum(s_local);
  for (int i = int(lane); i < n; i += 32) {
    x[base + i] = exp(x[base + i] - m) * inv_s;
  }
}
