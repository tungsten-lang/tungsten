// Reuse each selected K/V row across two query heads in the same GQA group.
// Adapted from the CUDA challenge's grouped QSA prefill dispatch; retain
// qsa_sdpa_selected_par's f32 dot, softmax tree, and value accumulation order.
// 256 threads/group, n_tok*n_heads/2 groups; even gqa_factor and n_heads.
// Two heads keep scratch below Metal's 32 KiB threadgroup memory limit.
// Provenance: docs/upstream-cuda-metal-2026-09-11.md.
#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(256)]]
kernel void qsa_sdpa_selected_group2(
    device const float *q [[buffer(0)]], device const float *k_cache [[buffer(1)]],
    device const float *v_cache [[buffer(2)]], device float *out [[buffer(3)]],
    device const int *sel [[buffer(4)]], device const int *ns [[buffer(5)]],
    constant int &gqa_factor [[buffer(6)]], constant int &n_heads [[buffer(7)]],
    constant int &kv_dim [[buffer(8)]], constant float &scale [[buffer(9)]],
    constant int &sel_stride [[buffer(10)]], constant int &n_tok [[buffer(11)]],
    uint tg [[threadgroup_position_in_grid]], uint tid [[thread_position_in_threadgroup]]) {
  threadgroup float scores[2][2051], qs[2][256], red[2][8];
  const int per_token = n_heads / 2;
  const int token = int(tg) / per_token;
  const int q_head = (int(tg) % per_token) * 2;
  if (token >= n_tok) return;
  const int kv_base = (q_head / gqa_factor) * 256;
  const int q_off = (token * n_heads + q_head) * 256;
  const device int *ts = sel + token * sel_stride;
  const int usable = min(ns[token], 2051);
  qs[0][tid] = q[q_off + int(tid)];
  qs[1][tid] = q[q_off + 256 + int(tid)];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = int(tid); p < usable; p += 256) {
    const device float *kr = k_cache + kv_base + ts[p] * kv_dim;
    float dp0 = 0.0f, dp1 = 0.0f;
    for (int i = 0; i < 256; ++i) {
      float key = kr[i];
      dp0 += qs[0][i] * key;
      dp1 += qs[1][i] * key;
    }
    scores[0][p] = dp0 * scale;
    scores[1][p] = dp1 * scale;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float lmx0 = -INFINITY, lmx1 = -INFINITY;
  for (int p = int(tid); p < usable; p += 256) {
    lmx0 = max(lmx0, scores[0][p]); lmx1 = max(lmx1, scores[1][p]);
  }
  float smx0 = simd_max(lmx0), smx1 = simd_max(lmx1);
  if ((tid & 31) == 0) { red[0][tid >> 5] = smx0; red[1][tid >> 5] = smx1; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float mx[2];
  for (int h = 0; h < 2; ++h)
    mx[h] = max(max(max(red[h][0], red[h][1]), max(red[h][2], red[h][3])),
                max(max(red[h][4], red[h][5]), max(red[h][6], red[h][7])));
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float lsum0 = 0.0f, lsum1 = 0.0f;
  for (int p = int(tid); p < usable; p += 256) {
    float e0 = fast::exp(scores[0][p] - mx[0]);
    float e1 = fast::exp(scores[1][p] - mx[1]);
    scores[0][p] = e0; scores[1][p] = e1;
    lsum0 += e0; lsum1 += e1;
  }
  float ssum0 = simd_sum(lsum0), ssum1 = simd_sum(lsum1);
  if ((tid & 31) == 0) { red[0][tid >> 5] = ssum0; red[1][tid >> 5] = ssum1; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float inv[2];
  for (int h = 0; h < 2; ++h) {
    float denom = red[h][0] + red[h][1] + red[h][2] + red[h][3] +
                  red[h][4] + red[h][5] + red[h][6] + red[h][7];
    inv[h] = denom == 0.0f ? 0.0f : 1.0f / denom;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float result0 = 0.0f, result1 = 0.0f;
  for (int p = 0; p < usable; ++p) {
    float value = v_cache[kv_base + ts[p] * kv_dim + int(tid)];
    result0 += scores[0][p] * value; result1 += scores[1][p] * value;
  }
  out[q_off + int(tid)] = result0 * inv[0];
  out[q_off + 256 + int(tid)] = result1 * inv[1];
}
