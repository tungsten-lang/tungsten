// Handwritten CUDA counterpart of router_softmax_topk10_warp.metal.
// One block of exactly 32 threads per token; finite f32 logits [rows,512],
// i32 indices [rows,10], f32 weights [rows,10]. No weight-format conversion.
// Provenance and validation scope: docs/upstream-cuda-metal-2026-09-11.md.
#include <cuda_runtime.h>
#include <math.h>
#include <stdint.h>

extern "C" __global__ __launch_bounds__(32) void router_softmax_topk10_multi_warp(
    const float *logits, int32_t *indices, float *weights) {
  const uint32_t row = blockIdx.x, lane = threadIdx.x;
  float values[16], reduce[16];
  for (uint32_t j = 0; j < 16; ++j) {
    values[j] = logits[(uint64_t)row * 512 + lane + j * 32];
    reduce[j] = values[j];
  }
  for (uint32_t stride = 8; stride; stride >>= 1)
    for (uint32_t j = 0; j < stride; ++j)
      reduce[j] = fmaxf(reduce[j], reduce[j + stride]);
  float max_logit = reduce[0];
  for (uint32_t stride = 16; stride; stride >>= 1)
    max_logit = fmaxf(max_logit, __shfl_xor_sync(0xffffffffu, max_logit, stride));
  for (uint32_t j = 0; j < 16; ++j) {
    values[j] = expf(values[j] - max_logit);
    reduce[j] = values[j];
  }
  for (uint32_t stride = 8; stride; stride >>= 1)
    for (uint32_t j = 0; j < stride; ++j)
      reduce[j] = reduce[j] + reduce[j + stride];
  float sum = reduce[0];
  for (uint32_t stride = 16; stride; stride >>= 1) {
    float other = __shfl_down_sync(0xffffffffu, sum, stride);
    if (lane < stride) sum = sum + other;
  }
  sum = __shfl_sync(0xffffffffu, sum, 0);
  for (uint32_t j = 0; j < 16; ++j) values[j] = values[j] / sum;

  uint32_t live = 0xffffu;
  float chosen[10];
  for (uint32_t k = 0; k < 10; ++k) {
    float best = -INFINITY;
    uint32_t index = UINT32_MAX;
    for (uint32_t j = 0; j < 16; ++j) {
      uint32_t e = lane + j * 32;
      if ((live & (1u << j)) &&
          (values[j] > best || (values[j] == best && e < index))) {
        best = values[j]; index = e;
      }
    }
    for (uint32_t stride = 16; stride; stride >>= 1) {
      float other = __shfl_down_sync(0xffffffffu, best, stride);
      uint32_t other_index = __shfl_down_sync(0xffffffffu, index, stride);
      if (lane + stride < 32 &&
          (other > best || (other == best && other_index < index))) {
        best = other; index = other_index;
      }
    }
    uint32_t winner = __shfl_sync(0xffffffffu, index, 0);
    if ((winner & 31u) == lane) live &= ~(1u << (winner >> 5));
    if (lane == 0) {
      indices[(uint64_t)row * 10 + k] = (int32_t)winner;
      chosen[k] = best;
    }
  }
  if (lane == 0) {
    float total = 0.0f;
    for (uint32_t k = 0; k < 10; ++k) total += chosen[k];
    for (uint32_t k = 0; k < 10; ++k) weights[(uint64_t)row * 10 + k] = chosen[k] / total;
  }
}
