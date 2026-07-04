#include <metal_stdlib>
using namespace metal;

constant int HEAD_DIM_FC      [[function_constant(0)]];
constant int HEAD_DIM_HALF_FC [[function_constant(1)]];
constant int N_HEADS_FC       [[function_constant(2)]];
constant int BATCH_FC         [[function_constant(3)]];

[[max_total_threads_per_threadgroup(32)]]
kernel void per_head_norm_rope_batch_fc(
  device float *x [[buffer(0)]],
  device const float *w [[buffer(1)]],
  device const float *cos_tab [[buffer(2)]],
  device const float *sin_tab [[buffer(3)]],
  constant float &inv_d [[buffer(4)]],
  constant float &eps [[buffer(5)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg) / N_HEADS_FC;
  int h = int(tg) - token * N_HEADS_FC;
  if (token >= BATCH_FC) return;

  int base = token * N_HEADS_FC * HEAD_DIM_FC + h * HEAD_DIM_FC;
  float sum_sq = 0.0f;
  for (int i = int(lane); i < HEAD_DIM_FC; i += 32) {
    float v = x[base + i];
    sum_sq += v * v;
  }
  float total = simd_sum(sum_sq);
  float rrms = 1.0f / sqrt(total * inv_d + eps);
  int rope_base = token * HEAD_DIM_HALF_FC;
  for (int p = int(lane); p < HEAD_DIM_HALF_FC; p += 32) {
    int lo = base + p;
    int hi = lo + HEAD_DIM_HALF_FC;
    float a = x[lo] * rrms * w[p];
    float b = x[hi] * rrms * w[p + HEAD_DIM_HALF_FC];
    float c = cos_tab[rope_base + p];
    float s = sin_tab[rope_base + p];
    x[lo] = a * c - b * s;
    x[hi] = a * s + b * c;
  }
}
