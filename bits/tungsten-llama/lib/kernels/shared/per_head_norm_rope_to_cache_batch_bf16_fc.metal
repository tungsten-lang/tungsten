// Same as per_head_norm_rope_to_cache_batch_fc but writes bf16 instead of f32.
// Used by the bf16-KV-cache long-prefill path.
#include <metal_stdlib>
using namespace metal;

constant int HEAD_DIM_FC      [[function_constant(0)]];
constant int HEAD_DIM_HALF_FC [[function_constant(1)]];
constant int N_HEADS_FC       [[function_constant(2)]];
constant int BATCH_FC         [[function_constant(3)]];

[[max_total_threads_per_threadgroup(32)]]
kernel void per_head_norm_rope_to_cache_batch_bf16_fc(
  device const float *k_now [[buffer(0)]],
  device const float *w [[buffer(1)]],
  device const float *cos_tab [[buffer(2)]],
  device const float *sin_tab [[buffer(3)]],
  device bfloat *cache [[buffer(4)]],
  constant int &row_size [[buffer(5)]],
  constant float &inv_d [[buffer(6)]],
  constant float &eps [[buffer(7)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]
) {
  int token = int(tg) / N_HEADS_FC;
  int h = int(tg) - token * N_HEADS_FC;
  if (token >= BATCH_FC) return;

  int base = token * N_HEADS_FC * HEAD_DIM_FC + h * HEAD_DIM_FC;
  int cache_base = token * row_size + h * HEAD_DIM_FC;
  float sum_sq = 0.0f;
  for (int i = int(lane); i < HEAD_DIM_FC; i += 32) {
    float v = k_now[base + i];
    sum_sq += v * v;
  }
  float total = simd_sum(sum_sq);
  float rrms = 1.0f / sqrt(total * inv_d + eps);
  int rope_base = token * HEAD_DIM_HALF_FC;
  for (int p = int(lane); p < HEAD_DIM_HALF_FC; p += 32) {
    float a = k_now[base + p] * rrms * w[p];
    float b = k_now[base + p + HEAD_DIM_HALF_FC] * rrms * w[p + HEAD_DIM_HALF_FC];
    float c = cos_tab[rope_base + p];
    float s = sin_tab[rope_base + p];
    cache[cache_base + p] = bfloat(a * c - b * s);
    cache[cache_base + p + HEAD_DIM_HALF_FC] = bfloat(a * s + b * c);
  }
}
