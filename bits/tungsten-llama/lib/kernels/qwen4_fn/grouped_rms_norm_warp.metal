// Wide-window normalization using the virtual-warp method from the Metal
// Qwen4 challenge. Reproduce Tungsten's 256-thread reduction exactly with
// 32, 64, or 128 threads. Experimental: no consistent win on M5 Max.
// See docs/upstream-cuda-metal-2026-09-11.md.
#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void grouped_rms_norm_multi_warp(
    device const float *x [[buffer(0)]], device const float *w [[buffer(1)]],
    device float *y [[buffer(2)]], constant int &d [[buffer(3)]],
    constant int &groups [[buffer(4)]], constant float &eps [[buffer(5)]],
    uint row [[threadgroup_position_in_grid]], uint lane [[thread_index_in_simdgroup]]) {
  int group = int(row) % groups;
  int base = int(row) * d;
  threadgroup float partials[8];
#pragma unroll
  for (uint warp = 0; warp < 8; ++warp) {
    float sum_sq = 0.0f;
    for (int i = int(warp * 32 + lane); i < d; i += 256) {
      float v = x[base + i];
      sum_sq += v * v;
    }
    float sm = simd_sum(sum_sq);
    if (lane == 0) partials[warp] = sm;
  }
  simdgroup_barrier(mem_flags::mem_threadgroup);
  float total = simd_sum(lane < 8 ? partials[lane] : 0.0f);
  float rrms = 1.0f / sqrt(total / float(d) + eps);
  for (int i = int(lane); i < d; i += 32)
    y[base + i] = x[base + i] * rrms * w[group * d + i];
}

[[max_total_threads_per_threadgroup(64)]]
kernel void grouped_rms_norm_multi_t64(
    device const float *x [[buffer(0)]], device const float *w [[buffer(1)]],
    device float *y [[buffer(2)]], constant int &d [[buffer(3)]],
    constant int &groups [[buffer(4)]], constant float &eps [[buffer(5)]],
    uint row [[threadgroup_position_in_grid]], uint lane [[thread_index_in_simdgroup]],
    uint simd [[simdgroup_index_in_threadgroup]], uint tid [[thread_position_in_threadgroup]]) {
  int group = int(row) % groups;
  int base = int(row) * d;
  threadgroup float partials[8];
#pragma unroll
  for (uint warp = simd; warp < 8; warp += 2) {
    float sum_sq = 0.0f;
    for (int i = int(warp * 32 + lane); i < d; i += 256) {
      float v = x[base + i];
      sum_sq += v * v;
    }
    float sm = simd_sum(sum_sq);
    if (lane == 0) partials[warp] = sm;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float total = simd_sum(lane < 8 ? partials[lane] : 0.0f);
  float rrms = 1.0f / sqrt(total / float(d) + eps);
  for (int i = int(tid); i < d; i += 64)
    y[base + i] = x[base + i] * rrms * w[group * d + i];
}

[[max_total_threads_per_threadgroup(128)]]
kernel void grouped_rms_norm_multi_t128(
    device const float *x [[buffer(0)]], device const float *w [[buffer(1)]],
    device float *y [[buffer(2)]], constant int &d [[buffer(3)]],
    constant int &groups [[buffer(4)]], constant float &eps [[buffer(5)]],
    uint row [[threadgroup_position_in_grid]], uint lane [[thread_index_in_simdgroup]],
    uint simd [[simdgroup_index_in_threadgroup]], uint tid [[thread_position_in_threadgroup]]) {
  int group = int(row) % groups;
  int base = int(row) * d;
  threadgroup float partials[8];
#pragma unroll
  for (uint warp = simd; warp < 8; warp += 4) {
    float sum_sq = 0.0f;
    for (int i = int(warp * 32 + lane); i < d; i += 256) {
      float v = x[base + i];
      sum_sq += v * v;
    }
    float sm = simd_sum(sum_sq);
    if (lane == 0) partials[warp] = sm;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float total = simd_sum(lane < 8 ? partials[lane] : 0.0f);
  float rrms = 1.0f / sqrt(total / float(d) + eps);
  for (int i = int(tid); i < d; i += 128)
    y[base + i] = x[base + i] * rrms * w[group * d + i];
}
