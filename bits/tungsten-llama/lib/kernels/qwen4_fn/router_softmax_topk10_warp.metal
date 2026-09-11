// One SIMD group per token, adapted from the CUDA/Metal Qwen4 challenge
// routers. See docs/upstream-cuda-metal-2026-09-11.md for provenance.
// Preserve Tungsten's full 512-way softmax, its stride-halving sum tree,
// probability-based selection, index tie break, and serial top-10 sum.
// Dispatch: one 32-thread group per token. Inputs must be finite logits.
#include <metal_stdlib>
using namespace metal;

static inline void fn_route_warp(
    device const float *logits, device int *indices, device float *weights,
    uint row, uint lane) {
#pragma clang fp reassociate(off)
  float values[16], reduce[16];
  for (uint j = 0; j < 16; ++j) {
    values[j] = logits[row * 512 + lane + j * 32];
    reduce[j] = values[j];
  }
  for (uint stride = 8; stride; stride >>= 1)
    for (uint j = 0; j < stride; ++j)
      reduce[j] = max(reduce[j], reduce[j + stride]);
  float max_logit = simd_max(reduce[0]);
  for (uint j = 0; j < 16; ++j) {
    values[j] = exp(values[j] - max_logit);
    reduce[j] = values[j];
  }
  // The first four levels are between virtual warps; the last five are
  // between lanes. This is the old 512-thread tree, not a reassociation.
  for (uint stride = 8; stride; stride >>= 1)
    for (uint j = 0; j < stride; ++j)
      reduce[j] = reduce[j] + reduce[j + stride];
  float sum = reduce[0];
  for (uint stride = 16; stride; stride >>= 1) {
    float other = simd_shuffle_down(sum, stride);
    if (lane < stride) sum = sum + other;
  }
  sum = simd_broadcast_first(sum);
  for (uint j = 0; j < 16; ++j) values[j] = values[j] / sum;

  uint live = 0xffffu;
  float chosen[10];
  for (uint k = 0; k < 10; ++k) {
    float best = -INFINITY;
    uint index = 0xffffffffu;
    for (uint j = 0; j < 16; ++j) {
      uint e = lane + j * 32;
      if ((live & (1u << j)) &&
          (values[j] > best || (values[j] == best && e < index))) {
        best = values[j]; index = e;
      }
    }
    float top = simd_max(best);
    uint winner = simd_min(best == top ? index : 0xffffffffu);
    if ((winner & 31u) == lane) live &= ~(1u << (winner >> 5));
    if (lane == 0) {
      indices[row * 10 + k] = int(winner);
      chosen[k] = top;
    }
  }
  if (lane == 0) {
    float total = 0.0f;
    for (uint k = 0; k < 10; ++k) total += chosen[k];
    for (uint k = 0; k < 10; ++k) weights[row * 10 + k] = chosen[k] / total;
  }
}

[[max_total_threads_per_threadgroup(32)]]
kernel void router_softmax_topk10_warp(
    device const float *logits [[buffer(0)]],
    device int *indices [[buffer(1)]], device float *weights [[buffer(2)]],
    uint lane [[thread_index_in_simdgroup]]) {
  fn_route_warp(logits, indices, weights, 0, lane);
}

[[max_total_threads_per_threadgroup(32)]]
kernel void router_softmax_topk10_multi_warp(
    device const float *logits [[buffer(0)]],
    device int *indices [[buffer(1)]], device float *weights [[buffer(2)]],
    uint row [[threadgroup_position_in_grid]], uint lane [[thread_index_in_simdgroup]]) {
  fn_route_warp(logits, indices, weights, row, lane);
}
